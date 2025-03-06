import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_settings.dart'; // 서버 설정 페이지 import

void main() {
  runApp(const SecurityMarkApp());
}

class SecurityMarkApp extends StatelessWidget {
  const SecurityMarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Security Mark',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(title: 'Security Mark'),
      debugShowCheckedModeBanner: false, // 디버그 배너 제거
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _imageFile;
  bool _isLoading = false;
  String _resultMessage = '';
  String? _watermarkedImageUrl;
  ImageSource? _selectedSource; // 어떤 소스를 선택했는지 추적

  // 서버 URL 설정 (기본값)
  String _serverUrl = 'http://10.0.2.2:5000';

  @override
  void initState() {
    super.initState();
    // 저장된 서버 URL 불러오기
    _loadServerUrl();
  }

  // 저장된 서버 URL 불러오기
  Future<void> _loadServerUrl() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? savedUrl = prefs.getString('server_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        setState(() {
          _serverUrl = savedUrl;
        });
      }
    } catch (e) {
      print('서버 URL 불러오기 오류: $e');
    }
  }

  // 서버 URL 업데이트
  void _updateServerUrl(String newUrl) {
    setState(() {
      _serverUrl = newUrl;
    });
  }

  // 서버 설정 페이지 열기
  void _openServerSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServerSettingsPage(
          currentUrl: _serverUrl,
          onUrlChanged: _updateServerUrl,
        ),
      ),
    );
  }

  // 이미지 선택 (갤러리)
  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _resultMessage = '';
          _selectedSource = ImageSource.gallery; // 갤러리 선택 표시
          _watermarkedImageUrl = null; // 새 이미지 선택 시 이전 결과 초기화
        });
      }
    } catch (e) {
      setState(() {
        _resultMessage = '갤러리 접근 중 오류가 발생했습니다: $e';
      });
    }
  }

  // 카메라로 사진 촬영
  Future<void> _takePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _resultMessage = '';
          _selectedSource = ImageSource.camera; // 카메라 선택 표시
          _watermarkedImageUrl = null; // 새 이미지 선택 시 이전 결과 초기화
        });
      }
    } catch (e) {
      setState(() {
        _resultMessage = '카메라 접근 중 오류가 발생했습니다: $e';
      });
    }
  }

  // 이미지 업로드 및 API 요청
  Future<void> _uploadImage() async {
    if (_imageFile == null) {
      setState(() {
        _resultMessage = '이미지를 선택하거나 촬영해주세요.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = '';
    });

    try {
      // 설정된 서버 URL 사용
      final url = Uri.parse('$_serverUrl/watermark');

      // Multipart 요청 생성
      var request = http.MultipartRequest('POST', url);

      // 이미지 파일 추가
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        _imageFile!.path,
        filename: _imageFile!.path.split('/').last,
      ));

      // 필요한 경우 추가 파라미터를 여기에 추가
      request.fields['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString();

      // 요청 전송 및 응답 대기
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // 성공적인 응답 처리
        final responseData = jsonDecode(response.body);

        // 워터마크가 적용된 이미지 URL이 응답에 포함된 경우
        String? watermarkedImageUrl;
        if (responseData.containsKey('watermarked_image_url')) {
          watermarkedImageUrl = responseData['watermarked_image_url'];
        }

        setState(() {
          _resultMessage = '이미지가 성공적으로 처리되었습니다.';
          _watermarkedImageUrl = watermarkedImageUrl;
        });
      } else {
        // 오류 응답 처리
        setState(() {
          _resultMessage = '오류가 발생했습니다. (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _resultMessage = '업로드 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          // 서버 설정 버튼 추가
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openServerSettings,
            tooltip: '서버 URL 설정',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 20),
              // 앱 설명
              const Center(
                child: Text(
                  '사진을 업로드하여 워터마크를 적용하세요',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // 현재 서버 URL 표시
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '서버: $_serverUrl',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 이미지 선택 버튼들
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: Icon(
                        Icons.photo_library,
                        color: _selectedSource == ImageSource.gallery ? Colors.green : null,
                      ),
                      label: Text(
                        '갤러리에서 선택',
                        style: TextStyle(
                          color: _selectedSource == ImageSource.gallery ? Colors.green : null,
                          fontWeight: _selectedSource == ImageSource.gallery ? FontWeight.bold : null,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: _selectedSource == ImageSource.gallery
                            ? Colors.green.withOpacity(0.1)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _takePicture,
                      icon: Icon(
                        Icons.camera_alt,
                        color: _selectedSource == ImageSource.camera ? Colors.green : null,
                      ),
                      label: Text(
                        '카메라로 촬영',
                        style: TextStyle(
                          color: _selectedSource == ImageSource.camera ? Colors.green : null,
                          fontWeight: _selectedSource == ImageSource.camera ? FontWeight.bold : null,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: _selectedSource == ImageSource.camera
                            ? Colors.green.withOpacity(0.1)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 업로드 버튼
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _uploadImage,
                icon: _isLoading
                    ? Container(
                  width: 24,
                  height: 24,
                  padding: const EdgeInsets.all(2.0),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                  ),
                )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isLoading ? '처리중...' : '업로드 및 워터마크 적용'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 20),

              // 결과 메시지
              if (_resultMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _resultMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),

              // 워터마크가 적용된 이미지 표시 (URL이 있는 경우)
              if (_watermarkedImageUrl != null && _imageFile != null)
                Column(
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      '원본 / 워터마크 적용 결과 비교:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // 원본 이미지
                        Expanded(
                          child: Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _imageFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        // 워터마크 적용 이미지
                        Expanded(
                          child: Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _watermarkedImageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Text(
                                      '이미지를 불러올 수 없습니다.',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}