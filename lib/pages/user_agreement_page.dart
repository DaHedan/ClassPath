import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 用户协议页：展示 [assets/user_agreement.txt] 全文，文本可长按复制。
class UserAgreementPage extends StatefulWidget {
  const UserAgreementPage({super.key});

  @override
  State<UserAgreementPage> createState() => _UserAgreementPageState();
}

class _UserAgreementPageState extends State<UserAgreementPage> {
  String? _text;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/user_agreement.txt').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text;
    return Scaffold(
      appBar: AppBar(title: const Text('用户协议')),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: SelectableText(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
    );
  }
}
