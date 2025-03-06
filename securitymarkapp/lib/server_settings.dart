import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 서버 URL 설정 화면
class ServerSettingsPage extends StatefulWidget {
  final String currentUrl;
  final Function(String) onUrlChanged;

  const ServerSettingsPage({
    Key? key,
    required this.currentUrl,
    required this.onUrlChanged,
  }) : super(key: key);

  @override
  _ServerSettingsPageState createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late TextEditingController _urlController;
  String _selectedPresetUrl = '';
  final List<String> _presetUrls = [
    'http://10.0.2.2:5000',  // Android 에뮬레이터
    'http://localhost:5000', // iOS 시뮬레이터
    'http://127.0.0.1:5000', // 루프백
  ];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentUrl);

    // 현재 URL이 프리셋 중 하나인지 확인
    if (_presetUrls.contains(widget.currentUrl)) {
      _selectedPresetUrl = widget.currentUrl;
    }

    // 현재 로컬 IP 주소 찾기 (실제 기기용)
    _findLocalIpAddress();
  }

  // 로컬 IP 주소를 찾아 프리셋에 추가 (실제 기기용)
  void _findLocalIpAddress() async {
    // 이 부분은 실제 IP 주소를 가져오는 로직으로 대체되어야 합니다.
    // 지금은 일단 하드코딩된 예시를 추가합니다.
    if (!_presetUrls.contains('http://192.168.0.12:5000')) {
      setState(() {
        _presetUrls.add('http://192.168.0.12:5000');
      });
    }
  }

  // URL을 SharedPreferences에 저장
  void _saveUrl(String url) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    widget.onUrlChanged(url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('서버 URL 설정'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 설명 텍스트
            const Text(
              '서버 URL을 직접 입력하거나 아래 프리셋 중에서 선택하세요:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),

            // URL 입력 필드
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '서버 URL',
                hintText: 'http://서버주소:포트',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),

            // 프리셋 URL 목록
            const Text(
              '프리셋 URL:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // 프리셋 URL 라디오 버튼 목록
            ...List<Widget>.generate(_presetUrls.length, (index) {
              final url = _presetUrls[index];
              String label = url;

              // URL에 따라 라벨 추가
              if (url.contains('10.0.2.2')) {
                label = '$url (Android 에뮬레이터용)';
              } else if (url.contains('localhost')) {
                label = '$url (iOS 시뮬레이터용)';
              } else if (url.contains('127.0.0.1')) {
                label = '$url (로컬호스트)';
              } else if (url.contains('192.168.')) {
                label = '$url (로컬 네트워크)';
              }

              return RadioListTile<String>(
                title: Text(label),
                value: url,
                groupValue: _selectedPresetUrl,
                onChanged: (value) {
                  setState(() {
                    _selectedPresetUrl = value!;
                    _urlController.text = value;
                  });
                },
              );
            }),

            const Spacer(),

            // 저장 버튼
            ElevatedButton(
              onPressed: () {
                if (_urlController.text.isNotEmpty) {
                  _saveUrl(_urlController.text);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL을 입력해주세요')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('저장', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}