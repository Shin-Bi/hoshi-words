import 'package:flutter/material.dart';

Future<void> showSourceInfoSheet(
  BuildContext context, {
  required int totalWords,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('공개 데모 안내')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('자체 작성 데모 단어 $totalWords개'),
            const SizedBox(height: 16),
            const Text(
              '어휘, 예문, 번역, 문법 및 회화 설명은 공개 데모를 위해 새로 작성했습니다. '
              '데모 1~5는 화면을 체험하기 위한 주제 묶음이며 시험 급수나 학습 난도를 뜻하지 않습니다.',
            ),
            const SizedBox(height: 16),
            const Text(
              '음성은 기기에 설치된 Android TTS를 사용합니다. 일본어 음성 데이터가 필요할 수 있습니다. '
              '분석 기능은 이 작은 데모 단어장과의 일치를 찾습니다.',
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: '별빛 단어 · 공개 데모',
              ),
              child: const Text('소프트웨어 라이선스'),
            ),
          ],
        ),
      ),
    ),
  );
}
