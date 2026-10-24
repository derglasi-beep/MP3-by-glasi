import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

enum HeartRateSensorStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class HeartRateSensorState {
  final HeartRateSensorStatus status;
  final String? deviceName;
  final String? deviceId;
  final int? bpm;
  final String? error;

  const HeartRateSensorState({
    required this.status,
    this.deviceName,
    this.deviceId,
    this.bpm,
    this.error,
  });

  const HeartRateSensorState.disconnected()
      : this(status: HeartRateSensorStatus.disconnected);

  HeartRateSensorState copyWith({
    HeartRateSensorStatus? status,
    String? deviceName,
    String? deviceId,
    int? bpm,
    String? error,
    bool clearError = false,
  }) =>
      HeartRateSensorState(
        status: status ?? this.status,
        deviceName: deviceName ?? this.deviceName,
        deviceId: deviceId ?? this.deviceId,
        bpm: bpm ?? this.bpm,
        error: clearError ? null : (error ?? this.error),
      );
}

class HeartRateSensorService {
  static const String heartRateServiceUuid = '180d';
  static const String heartRateMeasurementUuid = '2a37';

  final StreamController<HeartRateSensorState> _stateController =
      StreamController<HeartRateSensorState>.broadcast();
  final StreamController<List<BleDevice>> _devicesController =
      StreamController<List<BleDevice>>.broadcast();

  final Map<String, BleDevice> _devices = <String, BleDevice>{};
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connectionSub;
  BleCharacteristic? _heartRateCharacteristic;
  BleDevice? _connectedDevice;
  Timer? _scanTimer;

  HeartRateSensorState _state = const HeartRateSensorState.disconnected();

  HeartRateSensorState get state => _state;
  Stream<HeartRateSensorState> get stateStream => _stateController.stream;
  Stream<List<BleDevice>> get devicesStream => _devicesController.stream;
  List<BleDevice> get devices => _devices.values.toList(growable: false);

  void _emit(HeartRateSensorState next) {
    _state = next;
    _stateController.add(next);
  }

  Future<void> startScan({
    Duration duration = const Duration(seconds: 8),
  }) async {
    await stopScan();
    _devices.clear();
    _devicesController.add(const <BleDevice>[]);
    _emit(
      _state.copyWith(
        status: HeartRateSensorStatus.scanning,
        clearError: true,
      ),
    );

    try {
      await UniversalBle.requestPermissions();

      _scanSub = UniversalBle.scanStream.listen((device) {
        _devices[device.deviceId] = device;
        _devicesController.add(devices);
      });

      final systemDevices = await UniversalBle.getSystemDevices(
        withServices: const [heartRateServiceUuid],
      );
      for (final device in systemDevices) {
        _devices[device.deviceId] = device;
      }
      if (_devices.isNotEmpty) {
        _devicesController.add(devices);
      }

      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: const [heartRateServiceUuid],
        ),
        skipDuplicates: true,
      );

      _scanTimer = Timer(duration, () {
        unawaited(stopScan());
      });
    } catch (error) {
      await stopScan();
      _emit(
        HeartRateSensorState(
          status: HeartRateSensorStatus.error,
          error: _errorMessage(error),
        ),
      );
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    try {
      if (await UniversalBle.isScanning()) {
        await UniversalBle.stopScan();
      }
    } catch (_) {
      // A failed stop must not hide the devices already found.
    }
    await _scanSub?.cancel();
    _scanSub = null;

    if (_state.status == HeartRateSensorStatus.scanning) {
      _emit(const HeartRateSensorState.disconnected());
    }
  }

  Future<void> connect(BleDevice device) async {
    await stopScan();
    await disconnect();

    _emit(
      HeartRateSensorState(
        status: HeartRateSensorStatus.connecting,
        deviceName: _displayName(device),
        deviceId: device.deviceId,
      ),
    );

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      _connectionSub = device.connectionStream.listen((connected) {
        if (!connected && _connectedDevice?.deviceId == device.deviceId) {
          _emit(const HeartRateSensorState.disconnected());
        }
      });

      await device.discoverServices(timeout: const Duration(seconds: 15));
      final characteristic = await device.getCharacteristic(
        heartRateMeasurementUuid,
        service: heartRateServiceUuid,
        timeout: const Duration(seconds: 10),
      );
      _heartRateCharacteristic = characteristic;

      _valueSub = characteristic.onValueReceived.listen((value) {
        final bpm = decodeHeartRate(value);
        if (bpm == null) return;
        _emit(
          HeartRateSensorState(
            status: HeartRateSensorStatus.connected,
            deviceName: _displayName(device),
            deviceId: device.deviceId,
            bpm: bpm,
          ),
        );
      });

      await characteristic.notifications.subscribe(
        timeout: const Duration(seconds: 10),
      );

      _emit(
        HeartRateSensorState(
          status: HeartRateSensorStatus.connected,
          deviceName: _displayName(device),
          deviceId: device.deviceId,
        ),
      );
    } catch (error) {
      await disconnect();
      _emit(
        HeartRateSensorState(
          status: HeartRateSensorStatus.error,
          deviceName: _displayName(device),
          deviceId: device.deviceId,
          error: _errorMessage(error),
        ),
      );
    }
  }

  Future<void> disconnect() async {
    final characteristic = _heartRateCharacteristic;
    _heartRateCharacteristic = null;
    try {
      await characteristic?.unsubscribe();
    } catch (_) {}

    await _valueSub?.cancel();
    _valueSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;

    final device = _connectedDevice;
    _connectedDevice = null;
    if (device != null) {
      try {
        await device.disconnect(timeout: const Duration(seconds: 5));
      } catch (_) {}
    }

    if (_state.status != HeartRateSensorStatus.error) {
      _emit(const HeartRateSensorState.disconnected());
    }
  }

  static int? decodeHeartRate(Uint8List value) {
    if (value.length < 2) return null;

    final flags = value[0];
    final is16Bit = (flags & 0x01) != 0;
    if (!is16Bit) {
      return value[1];
    }

    if (value.length < 3) return null;
    return value[1] | (value[2] << 8);
  }

  String _displayName(BleDevice device) {
    final name = device.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'HF-Sensor';
  }

  String _errorMessage(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty) {
      return 'Bluetooth-Verbindung fehlgeschlagen.';
    }
    return message;
  }

  Future<void> dispose() async {
    _scanTimer?.cancel();
    await stopScan();
    await disconnect();
    await _devicesController.close();
    await _stateController.close();
  }
}
