import 'wifi_sensor_transport.dart';
import 'wifi_sensor_transport_cloud.dart';

WifiSensorTransport createWifiSensorTransport() {
  throw UnsupportedError('WiFi sensor transport is not available on this platform.');
}

WifiSensorTransport createCloudWifiSensorTransport() => CloudPollWifiSensorTransport();
