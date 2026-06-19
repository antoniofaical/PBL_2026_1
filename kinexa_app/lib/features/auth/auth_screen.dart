import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/boot/app_boot.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_button.dart';
import '../../core/widgets/kinexa_form_field.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../core/widgets/sync_brand_header.dart';
import '../../core/widgets/sync_version_footer.dart';
import '../../data/models/auth_session.dart';
import '../../providers.dart';
import '../../router.dart';

enum _AuthUiState { form, submitting }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  _AuthUiState _state = _AuthUiState.form;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCachedUsername();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadCachedUsername() async {
    final cached = await ref.read(authRepositoryProvider).cachedUsername();
    if (cached != null && mounted) {
      _username.text = cached;
    }
  }

  Future<void> _submit() async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Informe usuário e senha.');
      return;
    }

    setState(() {
      _state = _AuthUiState.submitting;
      _error = null;
    });

    try {
      final session = await ref.read(authRepositoryProvider).login(
            username: user,
            password: pass,
          );
      ref.read(authUserProvider.notifier).state = session.username;
      ref.read(offlineModeProvider.notifier).state = false;
      bootPhase.value = BootPhase.syncing;
      authGate.value = true;
      if (!mounted) return;
      context.go('/sync');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _AuthUiState.form;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _AuthUiState.form;
        _error = 'Falha ao conectar ao servidor. Verifique a internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const SyncBrandHeader(),
            const SizedBox(height: 24),
            Expanded(child: _formBody()),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: SyncVersionFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formBody() {
    final submitting = _state == _AuthUiState.submitting;

    return KinexaScrollReveal(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Icon(
            Symbols.lock,
            size: 72,
            color: AppColors.redPrimary,
          ),
          const SizedBox(height: 28),
          Text(
            'ENTRAR',
            style: AppTextStyles.mono(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Use sua conta Kinexa para sincronizar coletas com o servidor.',
            style: AppTextStyles.mono(
              size: 15,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          KinexaMetadataTextField(
            label: 'USUÁRIO',
            controller: _username,
            labelBackgroundColor: AppColors.popupBackground,
          ),
          const SizedBox(height: 20),
          KinexaMetadataTextField(
            label: 'SENHA',
            controller: _password,
            labelBackgroundColor: AppColors.popupBackground,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: AppTextStyles.mono(
                size: 14,
                color: AppColors.redLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 28),
          KinexaButton.round(
            label: submitting ? 'ENTRANDO...' : 'ENTRAR',
            onPressed: submitting ? null : _submit,
            expanded: true,
            enabled: !submitting,
          ),
        ],
      ),
    );
  }
}
