// lib/screens/auth/signup_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../services/points_service.dart';
import 'login_page.dart';
import '../../widgets/common/app_logo.dart';

class SignupPage extends StatefulWidget {
  final String? prefilledEmail;
  final String? prefilledName;
  final bool isEngineerInvite;
  final String? referralCode; // ① NEW

  const SignupPage({
    super.key,
    this.prefilledEmail,
    this.prefilledName,
    this.isEngineerInvite = false,
    this.referralCode, // ① NEW
  });

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  int _currentStep = 0;

  // ── Referral ── ②
  final _referralCodeController = TextEditingController();
  bool _referralValidating = false;
  bool? _referralValid; // null=not checked, true=valid, false=invalid
  String? _referrerName;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledEmail != null) {
      _emailController.text = widget.prefilledEmail!;
    }
    if (widget.prefilledName != null) {
      _nameController.text = widget.prefilledName!;
    }
    // ③ NEW: pre-fill referral code from deep link
    if (widget.referralCode != null && widget.referralCode!.isNotEmpty) {
      _referralCodeController.text = widget.referralCode!;
      // Validate after frame builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateReferralCode();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose(); // ④ NEW
    super.dispose();
  }

  // ⑤ NEW: referral code validation method
  Future<void> _validateReferralCode() async {
    final code = _referralCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _referralValid = null;
        _referrerName = null;
      });
      return;
    }

    setState(() {
      _referralValidating = true;
      _referralValid = null;
      _referrerName = null;
    });

    try {
      final result = await SupabaseConfig.client
          .from('referral_codes')
          .select('code, is_active, user_id, users!inner(full_name)')
          .eq('code', code.toUpperCase())
          .eq('is_active', true)
          .maybeSingle();

      if (!mounted) return;

      if (result != null) {
        final userData = result['users'] as Map<String, dynamic>?;
        setState(() {
          _referralValid = true;
          _referrerName = userData?['full_name'] as String? ?? 'A friend';
          _referralValidating = false;
        });
      } else {
        setState(() {
          _referralValid = false;
          _referrerName = null;
          _referralValidating = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Referral code validation error: $e');
      if (!mounted) return;
      setState(() {
        _referralValid = false;
        _referrerName = null;
        _referralValidating = false;
      });
    }
  }

  // ⑥ Modified _signup — applies referral + awards signup points
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final response = await SupabaseConfig.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'full_name': _nameController.text.trim(),
          'phone_number': _phoneController.text.trim(),
        },
      );

      if (response.user != null) {
        try {
          await SupabaseConfig.client.from('users').upsert({
            'id': response.user!.id,
            'email': _emailController.text.trim(),
            'full_name': _nameController.text.trim(),
            'company_name': _companyController.text.trim(),
            'phone_number': _phoneController.text.trim(),
            'role': widget.isEngineerInvite ? 'engineer' : 'customer',
          });
        } catch (dbError) {
          await SupabaseConfig.client.auth.signOut();
          debugPrint('❌ User row creation failed: $dbError');
          rethrow;
        }

        // ── Award signup points (fire-and-forget) ──
        PointsService.awardOnce(
            'account_creation', 100, 'Welcome to iConnect!');

        // ── NEW: Apply referral code if valid ──
        // M10: Normalize the code to uppercase before the RPC. The validation
        // query above already uppercases, but without the same normalization
        // here a user who typed "abc123" would pass validation (lookup is
        // case-insensitive) and then hit `apply_referral_code` with lowercase
        // input — which may or may not match depending on how strict the RPC
        // is about the `p_code` value. Always send the canonical form.
        final referralCode =
            _referralCodeController.text.trim().toUpperCase();
        if (referralCode.isNotEmpty && _referralValid == true) {
          try {
            await SupabaseConfig.client.rpc('apply_referral_code', params: {
              'p_referred_id': response.user!.id,
              'p_code': referralCode,
            });
            debugPrint('✅ Referral code applied: $referralCode');
          } catch (refErr) {
            debugPrint('⚠️ Referral apply error (non-fatal): $refErr');
            // Non-fatal — don't block signup
          }
        }

        if (mounted) _showSuccessDialog();
      } else {
        throw Exception(
            'Signup returned no user. The email may already be registered.');
      }
    } catch (e) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_friendlyError(e))),
            ],
          ),
          backgroundColor: isDark ? const Color(0xFFCF6679) : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('already registered') || msg.contains('already exists')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('weak password') || msg.contains('password')) {
      return 'Password is too weak. Please use at least 6 characters.';
    }
    if (msg.contains('invalid email') || msg.contains('valid email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Check your connection.';
    }
    if (msg.contains('too many')) {
      return 'Too many attempts. Please wait and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _showSuccessDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isDark
              ? const BorderSide(color: Brand.darkBorder, width: 1)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.lightGreen.withAlpha(((0.12) * 255).toInt())
                      : Brand.lightGreenSurface,
                  borderRadius: BorderRadius.circular(22),
                  border: isDark
                      ? Border.all(color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt()))
                      : null,
                ),
                child: Icon(Icons.check_circle_rounded,
                    color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
                    size: 40),
              ),
              const SizedBox(height: 20),
              Text('Account Created!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  )),
              const SizedBox(height: 10),
              Text('Welcome to i Connect!\nPlease sign in to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    height: 1.5,
                  )),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const LoginPage()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Brand.darkIconActive : Brand.royalBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Sign In Now',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: isDark ? Brand.darkCard : Brand.cardLight,
      ),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body: Stack(
          children: [
            // Top gradient
            Container(
              height: MediaQuery.of(context).size.height * 0.28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Brand.darkCard, Brand.darkCardElevated]
                      : [Brand.royalBlueDark, Brand.royalBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Brand.darkBorderLight.withAlpha(((0.15) * 255).toInt())
                            : Colors.white.withAlpha(((0.04) * 255).toInt()),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Brand.darkBorderLight.withAlpha(((0.1) * 255).toInt())
                            : Brand.lightGreen.withAlpha(((0.05) * 255).toInt()),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? Brand.darkCardElevated
                                : Colors.white.withAlpha(((0.15) * 255).toInt()),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  widget.isEngineerInvite
                                      ? 'Engineer Setup'
                                      : 'Create Account',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: isDark
                                        ? Brand.darkTextPrimary
                                        : Colors.white,
                                  )),
                              Text(
                                  widget.isEngineerInvite
                                      ? 'Complete your engineer profile'
                                      : 'Join iFrontiers Connect',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Colors.white.withAlpha(((0.55) * 255).toInt()),
                                  )),
                            ],
                          ),
                        ),
                        Opacity(
                          opacity: isDark ? 0.45 : 0.55,
                          child: const AppLogo.wordmark(height: 34, dark: true),
                        ),
                      ],
                    ),
                  ),

                  _buildStepIndicator(isDark),

                  if (widget.isEngineerInvite) _buildInviteBanner(isDark),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Form(
                        key: _formKey,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark ? Brand.darkCard : Brand.cardLight,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color:
                                  isDark ? Brand.darkBorder : Brand.borderLight,
                            ),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      color: Brand.royalBlue.withAlpha(15),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    )
                                  ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _currentStep == 0
                                ? _buildPersonalStep(isDark)
                                : _buildSecurityStep(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),

                  _buildBottomActions(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Brand.lightGreen.withAlpha(((0.08) * 255).toInt())
            : Brand.lightGreenSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Brand.lightGreen.withAlpha(((0.15) * 255).toInt())
              : Brand.lightGreen.withAlpha(((0.2) * 255).toInt()),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.engineering_rounded,
              color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
              size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You\'ve been invited as an engineer. Set your password to complete setup.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.lightGreenBright : Brand.lightGreenDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(40, 12, 40, 0),
      child: Row(
        children: [
          _buildStepDot(0, 'Personal Info', isDark),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: _currentStep >= 1
                  ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                  : isDark
                      ? Brand.darkBorderLight
                      : Colors.white.withAlpha(((0.2) * 255).toInt()),
            ),
          ),
          _buildStepDot(1, 'Security', isDark),
        ],
      ),
    );
  }

  Widget _buildStepDot(int step, String label, bool isDark) {
    final isActive = _currentStep >= step;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                : isDark
                    ? Brand.darkCardElevated
                    : Colors.white.withAlpha(((0.2) * 255).toInt()),
            shape: BoxShape.circle,
            border: isActive
                ? null
                : isDark
                    ? Border.all(color: Brand.darkBorderLight)
                    : null,
          ),
          child: Center(
            child: isActive && step < _currentStep
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text('${step + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark && !isActive
                          ? Brand.darkTextSecondary
                          : Colors.white,
                    )),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  _currentStep == step ? FontWeight.bold : FontWeight.w400,
              color: isDark
                  ? (_currentStep == step
                      ? Brand.darkTextPrimary
                      : Brand.darkTextSecondary)
                  : Colors.white.withAlpha(((0.8) * 255).toInt()),
            )),
      ],
    );
  }

  // ⑦ Modified: referral code field appended at bottom
  Widget _buildPersonalStep(bool isDark) {
    return Column(
      key: const ValueKey('personal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkIconActive.withAlpha(((0.12) * 255).toInt())
                  : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(10),
              border: isDark
                  ? Border.all(color: Brand.darkIconActive.withAlpha(((0.15) * 255).toInt()))
                  : null,
            ),
            child: Icon(Icons.person_rounded,
                color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                size: 18),
          ),
          const SizedBox(width: 12),
          Text('Personal Details',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
        ]),
        const SizedBox(height: 24),
        _buildLabel('Full Name', isDark),
        const SizedBox(height: 8),
        _buildField(
            controller: _nameController,
            hint: 'Enter your full name',
            icon: Icons.person_outline_rounded,
            isDark: isDark,
            readOnly: widget.prefilledName != null,
            validator: (v) =>
                v == null || v.isEmpty ? 'Please enter your name' : null),
        const SizedBox(height: 18),
        _buildLabel('Company Name', isDark),
        const SizedBox(height: 8),
        _buildField(
            controller: _companyController,
            hint: 'Enter company name',
            icon: Icons.business_rounded,
            isDark: isDark,
            validator: (v) =>
                v == null || v.isEmpty ? 'Please enter company name' : null),
        const SizedBox(height: 18),
        _buildLabel('Email Address', isDark),
        const SizedBox(height: 8),
        _buildField(
            controller: _emailController,
            hint: 'Enter your email',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            isDark: isDark,
            readOnly: widget.prefilledEmail != null,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter email';
              // H9: proper RFC-ish shape check; the previous contains('@')
              // guard accepted "a@" and "@b" which both fail at Supabase.
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                return 'Enter a valid email';
              }
              return null;
            }),
        const SizedBox(height: 18),
        _buildLabel('Phone Number', isDark),
        const SizedBox(height: 8),
        _buildField(
            controller: _phoneController,
            hint: 'Enter phone number',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            isDark: isDark,
            validator: (v) =>
                v == null || v.isEmpty ? 'Please enter phone number' : null),
        // ⑦ NEW: Referral code field (hidden for engineer invites)
        if (!widget.isEngineerInvite) ...[
          const SizedBox(height: 18),
          _buildLabel('Referral Code (optional)', isDark),
          const SizedBox(height: 8),
          _buildReferralCodeField(isDark),
        ],
      ],
    );
  }

  // ⑧ NEW: referral code field widget
  Widget _buildReferralCodeField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _referralValid == true
                  ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                  : _referralValid == false
                      ? Colors.red.withAlpha(128)
                      : (isDark ? Brand.darkBorderLight : Brand.borderLight),
              width: _referralValid != null ? 1.5 : 1.0,
            ),
          ),
          child: TextFormField(
            controller: _referralCodeController,
            textCapitalization: TextCapitalization.characters,
            readOnly:
                widget.referralCode != null && widget.referralCode!.isNotEmpty,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
            onChanged: (val) {
              // Reset validation when user types
              if (_referralValid != null) {
                setState(() {
                  _referralValid = null;
                  _referrerName = null;
                });
              }
            },
            onFieldSubmitted: (_) => _validateReferralCode(),
            onEditingComplete: _validateReferralCode,
            decoration: InputDecoration(
              hintText: 'e.g. REF-A1B2C3D4',
              hintStyle: TextStyle(
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.5,
              ),
              prefixIcon: Icon(Icons.card_giftcard_rounded,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  size: 20),
              suffixIcon: _referralValidating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.royalBlue),
                      ),
                    )
                  : _referralValid == true
                      ? const Icon(Icons.check_circle_rounded,
                          color: Brand.lightGreenBright, size: 22)
                      : _referralValid == false
                          ? Icon(Icons.cancel_rounded,
                              color: Colors.red.withAlpha(179), size: 22)
                          : _referralCodeController.text.trim().isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.search_rounded,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight,
                                      size: 20),
                                  onPressed: _validateReferralCode,
                                )
                              : null,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  width: 1.5,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        // ── Validation feedback ──
        if (_referralValid == true && _referrerName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.lightGreen.withAlpha(20)
                        : Brand.lightGreenSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Brand.lightGreen.withAlpha(isDark ? 38 : 51)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_rounded,
                          size: 14,
                          color: isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreenDark),
                      const SizedBox(width: 6),
                      Text(
                        'Referred by $_referrerName',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreenDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_referralValid == false)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Invalid or expired referral code',
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.withAlpha(isDark ? 204 : 255),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSecurityStep(bool isDark) {
    return Column(
      key: const ValueKey('security'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.lightGreen.withAlpha(((0.12) * 255).toInt())
                  : Brand.lightGreenSurface,
              borderRadius: BorderRadius.circular(10),
              border: isDark
                  ? Border.all(color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt()))
                  : null,
            ),
            child: Icon(Icons.shield_rounded,
                color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
                size: 18),
          ),
          const SizedBox(width: 12),
          Text('Set Password',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
        ]),
        const SizedBox(height: 10),
        Text('Create a strong password for your account',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            )),
        const SizedBox(height: 24),
        _buildLabel('Password', isDark),
        const SizedBox(height: 8),
        _buildPasswordField(
            controller: _passwordController,
            hint: 'Create password',
            isConfirm: false,
            isDark: isDark,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter a password';
              if (v.length < 6) return 'At least 6 characters';
              return null;
            }),
        const SizedBox(height: 18),
        _buildLabel('Confirm Password', isDark),
        const SizedBox(height: 8),
        _buildPasswordField(
            controller: _confirmPasswordController,
            hint: 'Confirm password',
            isConfirm: true,
            isDark: isDark,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm password';
              if (v != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            }),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight,
            ),
          ),
          child: Column(
            children: [
              _buildTip(Icons.check_circle_rounded, 'At least 6 characters',
                  _passwordController.text.length >= 6, isDark),
              const SizedBox(height: 6),
              _buildTip(
                  Icons.check_circle_rounded,
                  'Passwords match',
                  _passwordController.text.isNotEmpty &&
                      _passwordController.text ==
                          _confirmPasswordController.text,
                  isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTip(IconData icon, String text, bool isValid, bool isDark) {
    return Row(children: [
      Icon(icon,
          size: 16,
          color: isValid
              ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
              : isDark
                  ? Brand.darkTextTertiary
                  : Brand.subtleLight),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
            fontSize: 12,
            color: isValid
                ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                : isDark
                    ? Brand.darkTextTertiary
                    : Brand.subtleLight,
            fontWeight: isValid ? FontWeight.w600 : FontWeight.normal,
          )),
    ]);
  }

  Widget _buildLabel(String text, bool isDark) {
    return Text(text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ));
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      validator: validator,
      style: TextStyle(
        fontSize: 15,
        color: readOnly
            ? (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
            : (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon,
            color: isDark ? Brand.darkIconActive : Brand.royalBlue, size: 20),
        suffixIcon: readOnly
            ? Icon(Icons.lock_rounded,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                size: 16)
            : null,
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: readOnly
                ? (isDark ? Brand.darkBorderLight : Brand.borderLight)
                : (isDark ? Brand.darkIconActive : Brand.royalBlue),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool isConfirm,
    required bool isDark,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isConfirm ? _obscureConfirm : _obscurePassword,
      validator: validator,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontSize: 15,
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          fontSize: 14,
        ),
        prefixIcon: Icon(Icons.lock_rounded,
            color: isDark ? Brand.darkIconActive : Brand.royalBlue, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            (isConfirm ? _obscureConfirm : _obscurePassword)
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            size: 20,
          ),
          onPressed: () => setState(() {
            if (isConfirm) {
              _obscureConfirm = !_obscureConfirm;
            } else {
              _obscurePassword = !_obscurePassword;
            }
          }),
        ),
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildBottomActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
            width: 1,
          ),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(15),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                )
              ],
      ),
      child: SafeArea(
        top: false,
        child: _currentStep == 0
            ? SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    final name = _nameController.text.trim();
                    final email = _emailController.text.trim();
                    final phone = _phoneController.text.trim();
                    final company = _companyController.text.trim();

                    String? error;
                    if (name.isEmpty) {
                      error = 'Please enter your full name';
                    } else if (company.isEmpty) {
                      error = 'Please enter your company name';
                    } else if (email.isEmpty ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(email)) {
                      error = 'Please enter a valid email address';
                    } else if (phone.isEmpty) {
                      error = 'Please enter your phone number';
                    }

                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(error),
                        backgroundColor:
                            isDark ? const Color(0xFFCF6679) : Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                      ));
                      return;
                    }

                    setState(() => _currentStep = 1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [Brand.darkIconActive, Brand.royalBlueGlow]
                            : [Brand.royalBlueDark, Brand.royalBlueLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Brand.royalBlue.withAlpha(89),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Continue',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              )
            : Row(children: [
                GestureDetector(
                  onTap: () => setState(() => _currentStep = 0),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            isDark ? Brand.darkBorderLight : Brand.borderLight,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        color:
                            isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                        size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _signup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [Brand.lightGreenBright, Brand.lightGreen]
                              : [Brand.lightGreenDark, Brand.lightGreenBright],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Brand.lightGreen.withAlpha(69),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text('Create Account',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          letterSpacing: 0.2)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ]),
      ),
    );
  }
}
