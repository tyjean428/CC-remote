import 'dart:convert';
import 'dart:io';

import 'saved_devices.dart';

void requirePrivateDeviceTarget(String id) {
  if (id.contains('@') ||
      id.contains(':') ||
      InternetAddress.tryParse(id) != null) {
    throw const DeviceValidationException('请输入设备 ID，当前连接方式不支持网络地址');
  }
}

void requirePrivateConnectionService(
    {required String server, required String publicKey}) {
  if (server.trim().isEmpty) {
    throw const DeviceValidationException('尚未填写 ID 服务器，请配置连接服务');
  }
  if (publicKey.trim().isEmpty) {
    throw const DeviceValidationException('尚未填写服务器公钥（Key），请配置连接服务');
  }
  var validKey = false;
  try {
    validKey = base64.decode(base64.normalize(publicKey.trim())).length == 32;
  } on FormatException {
    validKey = false;
  }
  if (!validKey) {
    throw const DeviceValidationException('服务器公钥（Key）不完整或格式不正确，请粘贴完整公钥');
  }
}
