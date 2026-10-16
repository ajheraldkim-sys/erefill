import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../services/gmail_binding_service.dart';

class GmailBindingCard extends StatefulWidget {
  const GmailBindingCard({super.key, this.onVerified});

  final VoidCallback? onVerified;

  @override
  State<GmailBindingCard> createState() => _GmailBindingCardState();
}

class _GmailBindingCardState extends State<GmailBindingCard> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _service = GmailBindingService.instance;

  bool _isCheckingStatus = true;
  bool _isVerified = false;
  bool _isEditing = false;
  bool _isCodeSent = false;
  bool _isSending = false;
  bool _isVerifying = false;
  bool _awaitingCurrentEmailCode = false;
  GmailVerificationType _verificationType = GmailVerificationType.emailChange;
  String? _currentEmailBeforeChange;
  String? _errorMessage;
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final verified = await _service.checkGmailVerificationStatus();
      if (!mounted) return;
      setState(() {
        _isVerified = verified;
        if (verified) {
          _emailController.text = _service.currentEmail ?? '';
        }
        _isCheckingStatus = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCheckingStatus = false;
        _errorMessage = _messageFor(error);
      });
    }
  }

  Future<void> _sendCode() async {
    if (_emailFormKey.currentState != null &&
        !(_emailFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final currentEmail = _service.currentEmail;
      final verificationType = await _service.sendVerificationCode(
        _emailController.text,
      );
      if (!mounted) return;
      setState(() {
        _currentEmailBeforeChange = currentEmail;
        _verificationType = verificationType;
        _awaitingCurrentEmailCode = false;
        _isCodeSent = true;
        _isSending = false;
      });
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification code sent to ${_emailController.text.trim()}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = _messageFor(error);
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final emailToVerify = _awaitingCurrentEmailCode
          ? _currentEmailBeforeChange
          : _emailController.text;
      final isVerified = await _service.verifyOtpCode(
        gmailAddress: _emailController.text,
        emailToVerify: emailToVerify ?? '',
        otpCode: _codeController.text,
        type: _verificationType,
      );
      if (!mounted) return;

      if (!isVerified) {
        final canConfirmCurrentEmail =
            _verificationType == GmailVerificationType.emailChange &&
            !_awaitingCurrentEmailCode &&
            (_currentEmailBeforeChange?.isNotEmpty ?? false);
        setState(() {
          _isVerifying = false;
          _awaitingCurrentEmailCode = canConfirmCurrentEmail;
          if (canConfirmCurrentEmail) {
            _codeController.clear();
            _errorMessage = null;
          } else {
            _errorMessage =
                'Email verification is not complete. Request a new code and try again.';
          }
        });
        return;
      }

      setState(() {
        _isVerifying = false;
        _isVerified = true;
        _isEditing = false;
        _isCodeSent = false;
        _codeController.clear();
      });
      widget.onVerified?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = _messageFor(error);
      });
    }
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) timer.cancel();
      });
    });
  }

  void _editEmail() {
    _countdownTimer?.cancel();
    setState(() {
      _isEditing = true;
      _isCodeSent = false;
      _awaitingCurrentEmailCode = false;
      _resendCountdown = 0;
      _errorMessage = null;
      _codeController.clear();
    });
  }

  String _messageFor(Object error) {
    if (error is AuthException) return error.message;
    final message = error.toString().replaceFirst(
      RegExp(r'^(Exception|StateError|FormatException):\s*|^Bad state:\s*'),
      '',
    );
    return message;
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingStatus) {
      return _card(
        context,
        const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_isVerified && !_isEditing) return _buildVerifiedState(context);
    if (_isCodeSent) return _buildCodeState(context);
    return _buildEmailState(context);
  }

  Widget _buildVerifiedState(BuildContext context) {
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.uiSuccess),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Email verified',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: _editEmail, child: const Text('Change')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _service.currentEmail ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Used for account sign-in and recovery.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppUi.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailState(BuildContext context) {
    return _card(
      context,
      Form(
        key: _emailFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Change email address' : 'Verify your email',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'We’ll send a confirmation code to your Gmail address. Your email changes after you verify it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppUi.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              enabled: !_isSending,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Gmail address',
                hintText: 'name@gmail.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter your Gmail address.';
                if (!RegExp(
                  r'^[a-zA-Z0-9._%+-]+@gmail\.com$',
                ).hasMatch(email)) {
                  return 'Enter a valid Gmail address.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _sendCode(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _errorNotice(context, _errorMessage!),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSending ? null : _sendCode,
                child: _isSending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send 6-Digit Code'),
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _isEditing = false;
                    _errorMessage = null;
                  }),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCodeState(BuildContext context) {
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _awaitingCurrentEmailCode
                ? 'Confirm your current email'
                : 'Check your inbox',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _awaitingCurrentEmailCode
                ? 'For security, confirm your current email (${_currentEmailBeforeChange ?? ''}) to finish changing your sign-in email.'
                : 'Enter the 6-digit code sent to ${_emailController.text.trim()}. Your account email will update after verification.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppUi.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            enabled: !_isVerifying,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              letterSpacing: 10,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '------',
              labelText: 'Verification code',
            ),
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _verifyCode(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _errorNotice(context, _errorMessage!),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isVerifying ? null : _verifyCode,
              child: _isVerifying
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify email'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _editEmail,
                child: const Text('Change address'),
              ),
              TextButton(
                onPressed: _resendCountdown == 0 && !_isSending
                    ? () => _sendCode()
                    : null,
                child: Text(
                  _isSending
                      ? 'Sending...'
                      : _resendCountdown == 0
                      ? 'Resend code'
                      : 'Resend in ${_resendCountdown}s',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorNotice(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: AppUi.cardRadius,
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: AppUi.cardPadding,
      decoration: AppUi.cardDecorationOf(context),
      child: child,
    );
  }
}
