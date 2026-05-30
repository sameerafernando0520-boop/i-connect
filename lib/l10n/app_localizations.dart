import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_si.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('si'),
    Locale('ta')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'i Connect'**
  String get appName;

  /// No description provided for @companyName.
  ///
  /// In en, this message translates to:
  /// **'iFrontiers (Pvt) Ltd'**
  String get companyName;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'LKR'**
  String get currency;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'Rs.'**
  String get currencySymbol;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get commonFilter;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commonSend;

  /// No description provided for @commonView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get commonView;

  /// No description provided for @commonMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// No description provided for @commonShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show All'**
  String get commonShowAll;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get commonSeeAll;

  /// No description provided for @commonViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get commonViewAll;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get commonProcessing;

  /// No description provided for @commonSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get commonSaving;

  /// No description provided for @commonDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting...'**
  String get commonDeleting;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get commonCopied;

  /// No description provided for @commonSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get commonSaved;

  /// No description provided for @commonDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get commonDeleted;

  /// No description provided for @commonUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get commonUpdated;

  /// No description provided for @commonCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get commonCreated;

  /// No description provided for @commonEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get commonEnabled;

  /// No description provided for @commonDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get commonDisabled;

  /// No description provided for @commonActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive;

  /// No description provided for @commonInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get commonInactive;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @commonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get commonOther;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @commonNa.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get commonNa;

  /// No description provided for @commonNoData.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get commonNoData;

  /// No description provided for @commonNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get commonNoResults;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get commonSelectDate;

  /// No description provided for @commonSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select Time'**
  String get commonSelectTime;

  /// No description provided for @commonPickImage.
  ///
  /// In en, this message translates to:
  /// **'Pick Image'**
  String get commonPickImage;

  /// No description provided for @commonTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get commonTakePhoto;

  /// No description provided for @commonChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get commonChooseGallery;

  /// No description provided for @commonUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get commonUploading;

  /// No description provided for @commonSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get commonSuccess;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get commonWarning;

  /// No description provided for @commonInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get commonInfo;

  /// No description provided for @commonAreYouSure.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get commonAreYouSure;

  /// No description provided for @commonCannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get commonCannotUndo;

  /// No description provided for @commonNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get commonNoInternet;

  /// No description provided for @commonPullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get commonPullToRefresh;

  /// No description provided for @labelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get labelEmail;

  /// No description provided for @labelPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get labelPassword;

  /// No description provided for @labelConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get labelConfirmPassword;

  /// No description provided for @labelPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get labelPhone;

  /// No description provided for @labelFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get labelFullName;

  /// No description provided for @labelCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get labelCompanyName;

  /// No description provided for @labelCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get labelCity;

  /// No description provided for @labelAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get labelAddress;

  /// No description provided for @labelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get labelDate;

  /// No description provided for @labelTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get labelTime;

  /// No description provided for @labelDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get labelDuration;

  /// No description provided for @labelStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get labelStatus;

  /// No description provided for @labelPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get labelPriority;

  /// No description provided for @labelCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get labelCategory;

  /// No description provided for @labelType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get labelType;

  /// No description provided for @labelDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get labelDescription;

  /// No description provided for @labelNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get labelNotes;

  /// No description provided for @labelAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get labelAmount;

  /// No description provided for @labelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get labelTotal;

  /// No description provided for @labelTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get labelTax;

  /// No description provided for @labelSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get labelSubtotal;

  /// No description provided for @labelDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get labelDiscount;

  /// No description provided for @labelQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get labelQuantity;

  /// No description provided for @labelPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get labelPrice;

  /// No description provided for @labelUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get labelUnitPrice;

  /// No description provided for @labelSerialNumber.
  ///
  /// In en, this message translates to:
  /// **'Serial Number'**
  String get labelSerialNumber;

  /// No description provided for @labelModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get labelModel;

  /// No description provided for @labelBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get labelBrand;

  /// No description provided for @labelSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get labelSubject;

  /// No description provided for @labelLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get labelLocation;

  /// No description provided for @labelRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get labelRating;

  /// No description provided for @labelFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get labelFeedback;

  /// No description provided for @labelReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get labelReference;

  /// No description provided for @labelDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get labelDueDate;

  /// No description provided for @labelStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get labelStartDate;

  /// No description provided for @labelEndDate.
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get labelEndDate;

  /// No description provided for @labelCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get labelCreatedAt;

  /// No description provided for @labelUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get labelUpdatedAt;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get authWelcomeBack;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get authSignIn;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authSignUp;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authCreateAccount;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue to i Connect'**
  String get authLoginSubtitle;

  /// No description provided for @authSignupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join i Connect to get started'**
  String get authSignupSubtitle;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordHint;

  /// No description provided for @authConfirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get authConfirmPasswordHint;

  /// No description provided for @authFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get authFullNameHint;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get authPhoneHint;

  /// No description provided for @authCompanyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your company name'**
  String get authCompanyHint;

  /// No description provided for @authReferralCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Referral code (optional)'**
  String get authReferralCodeHint;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get authForgotPassword;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHaveAccount;

  /// No description provided for @authLoginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLoginButton;

  /// No description provided for @authRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get authRegisterButton;

  /// No description provided for @authSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get authSigningIn;

  /// No description provided for @authCreatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account...'**
  String get authCreatingAccount;

  /// No description provided for @authPasswordsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get authPasswordsNoMatch;

  /// No description provided for @authAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully!'**
  String get authAccountCreated;

  /// No description provided for @authLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Login successful'**
  String get authLoginSuccess;

  /// No description provided for @authLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get authLogout;

  /// No description provided for @authLogoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get authLogoutTitle;

  /// No description provided for @authLogoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get authLogoutConfirm;

  /// No description provided for @authLoggingOut.
  ///
  /// In en, this message translates to:
  /// **'Logging out...'**
  String get authLoggingOut;

  /// No description provided for @authWelcomeNew.
  ///
  /// In en, this message translates to:
  /// **'Welcome to i Connect!'**
  String get authWelcomeNew;

  /// No description provided for @authTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'By creating an account, you agree to our '**
  String get authTermsPrefix;

  /// No description provided for @authTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get authTermsLink;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get navCatalog;

  /// No description provided for @navTickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get navTickets;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get navSupport;

  /// No description provided for @navMachines.
  ///
  /// In en, this message translates to:
  /// **'My Machines'**
  String get navMachines;

  /// No description provided for @navKnowledgeBase.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get navKnowledgeBase;

  /// No description provided for @navMachinesShort.
  ///
  /// In en, this message translates to:
  /// **'Machines'**
  String get navMachinesShort;

  /// No description provided for @navKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get navKnowledge;

  /// No description provided for @navNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'My Schedule'**
  String get navSchedule;

  /// No description provided for @navInquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get navInquiries;

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navEngineers.
  ///
  /// In en, this message translates to:
  /// **'Engineers'**
  String get navEngineers;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @homeGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning'**
  String get homeGoodMorning;

  /// No description provided for @homeGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon'**
  String get homeGoodAfternoon;

  /// No description provided for @homeGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening'**
  String get homeGoodEvening;

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}!'**
  String homeWelcome(String name);

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get homeQuickActions;

  /// No description provided for @homeRecentTickets.
  ///
  /// In en, this message translates to:
  /// **'Recent Tickets'**
  String get homeRecentTickets;

  /// No description provided for @homeNoRecentTickets.
  ///
  /// In en, this message translates to:
  /// **'No recent tickets'**
  String get homeNoRecentTickets;

  /// No description provided for @homeViewAllTickets.
  ///
  /// In en, this message translates to:
  /// **'View All Tickets'**
  String get homeViewAllTickets;

  /// No description provided for @homeMyMachines.
  ///
  /// In en, this message translates to:
  /// **'My Machines'**
  String get homeMyMachines;

  /// No description provided for @homeNoMachines.
  ///
  /// In en, this message translates to:
  /// **'No registered machines'**
  String get homeNoMachines;

  /// No description provided for @homePointsBalance.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String homePointsBalance(int points);

  /// No description provided for @homeStreak.
  ///
  /// In en, this message translates to:
  /// **'{days}-day streak'**
  String homeStreak(int days);

  /// No description provided for @homeDailyLoginReward.
  ///
  /// In en, this message translates to:
  /// **'Daily login reward earned!'**
  String get homeDailyLoginReward;

  /// No description provided for @homeCurrentTier.
  ///
  /// In en, this message translates to:
  /// **'Current Tier'**
  String get homeCurrentTier;

  /// No description provided for @homePromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get homePromotions;

  /// No description provided for @homeExploreMore.
  ///
  /// In en, this message translates to:
  /// **'Explore More'**
  String get homeExploreMore;

  /// No description provided for @homeServiceDue.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get homeServiceDue;

  /// No description provided for @homeWarrantyExpiring.
  ///
  /// In en, this message translates to:
  /// **'Warranty expiring soon'**
  String get homeWarrantyExpiring;

  /// No description provided for @homeConnectionIssue.
  ///
  /// In en, this message translates to:
  /// **'Connection Issue'**
  String get homeConnectionIssue;

  /// No description provided for @homeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get homeRecentActivity;

  /// No description provided for @homeBrowseCatalog.
  ///
  /// In en, this message translates to:
  /// **'Browse Catalog'**
  String get homeBrowseCatalog;

  /// No description provided for @homeBrowseCatalogDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse our catalog to explore and get started'**
  String get homeBrowseCatalogDesc;

  /// No description provided for @catalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Machine Catalog'**
  String get catalogTitle;

  /// No description provided for @catalogSearch.
  ///
  /// In en, this message translates to:
  /// **'Search machines...'**
  String get catalogSearch;

  /// No description provided for @catalogCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get catalogCategories;

  /// No description provided for @catalogAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get catalogAllCategories;

  /// No description provided for @catalogFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get catalogFilter;

  /// No description provided for @catalogSort.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get catalogSort;

  /// No description provided for @catalogPriceLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: Low to High'**
  String get catalogPriceLowHigh;

  /// No description provided for @catalogPriceHighLow.
  ///
  /// In en, this message translates to:
  /// **'Price: High to Low'**
  String get catalogPriceHighLow;

  /// No description provided for @catalogNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest First'**
  String get catalogNewest;

  /// No description provided for @catalogSpecifications.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get catalogSpecifications;

  /// No description provided for @catalogFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get catalogFeatures;

  /// No description provided for @catalogApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get catalogApplications;

  /// No description provided for @catalogDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get catalogDescription;

  /// No description provided for @catalogRelatedMachines.
  ///
  /// In en, this message translates to:
  /// **'Related Machines'**
  String get catalogRelatedMachines;

  /// No description provided for @catalogNoMachines.
  ///
  /// In en, this message translates to:
  /// **'No machines found'**
  String get catalogNoMachines;

  /// No description provided for @catalogSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get catalogSaved;

  /// No description provided for @catalogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get catalogSave;

  /// No description provided for @catalogRemoveSaved.
  ///
  /// In en, this message translates to:
  /// **'Removed from saved'**
  String get catalogRemoveSaved;

  /// No description provided for @catalogAddedSaved.
  ///
  /// In en, this message translates to:
  /// **'Added to saved'**
  String get catalogAddedSaved;

  /// No description provided for @catalogRecentlyViewed.
  ///
  /// In en, this message translates to:
  /// **'Recently Viewed'**
  String get catalogRecentlyViewed;

  /// No description provided for @catalogOrderNow.
  ///
  /// In en, this message translates to:
  /// **'Order Now'**
  String get catalogOrderNow;

  /// No description provided for @catalogRequestQuote.
  ///
  /// In en, this message translates to:
  /// **'Request Quote'**
  String get catalogRequestQuote;

  /// No description provided for @catalogViewBrochure.
  ///
  /// In en, this message translates to:
  /// **'View Brochure'**
  String get catalogViewBrochure;

  /// No description provided for @catalogWatchVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch Video'**
  String get catalogWatchVideo;

  /// No description provided for @catalogMachineDetails.
  ///
  /// In en, this message translates to:
  /// **'Machine Details'**
  String get catalogMachineDetails;

  /// No description provided for @catalogPriceDisplay.
  ///
  /// In en, this message translates to:
  /// **'Rs. {price}'**
  String catalogPriceDisplay(String price);

  /// No description provided for @catalogPriceOnRequest.
  ///
  /// In en, this message translates to:
  /// **'Price on Request'**
  String get catalogPriceOnRequest;

  /// No description provided for @catalogSortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get catalogSortDefault;

  /// No description provided for @catalogSortBrand.
  ///
  /// In en, this message translates to:
  /// **'By Brand'**
  String get catalogSortBrand;

  /// No description provided for @catalogFilterBrand.
  ///
  /// In en, this message translates to:
  /// **'Filter by Brand'**
  String get catalogFilterBrand;

  /// No description provided for @catalogOwned.
  ///
  /// In en, this message translates to:
  /// **'OWNED'**
  String get catalogOwned;

  /// No description provided for @catalogMachineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Machine no longer available'**
  String get catalogMachineUnavailable;

  /// No description provided for @catalogNoMachinesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No machines available at the moment'**
  String get catalogNoMachinesAvailable;

  /// No description provided for @ticketTitle.
  ///
  /// In en, this message translates to:
  /// **'My Tickets'**
  String get ticketTitle;

  /// No description provided for @ticketCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Ticket'**
  String get ticketCreate;

  /// No description provided for @ticketCreateNew.
  ///
  /// In en, this message translates to:
  /// **'New Support Ticket'**
  String get ticketCreateNew;

  /// No description provided for @ticketNumber.
  ///
  /// In en, this message translates to:
  /// **'#{number}'**
  String ticketNumber(String number);

  /// No description provided for @ticketSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get ticketSubject;

  /// No description provided for @ticketSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'Brief description of the issue'**
  String get ticketSubjectHint;

  /// No description provided for @ticketDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get ticketDescription;

  /// No description provided for @ticketDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue in detail...'**
  String get ticketDescriptionHint;

  /// No description provided for @ticketSelectMachine.
  ///
  /// In en, this message translates to:
  /// **'Select Machine'**
  String get ticketSelectMachine;

  /// No description provided for @ticketSelectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get ticketSelectCategory;

  /// No description provided for @ticketSelectPriority.
  ///
  /// In en, this message translates to:
  /// **'Select Priority'**
  String get ticketSelectPriority;

  /// No description provided for @ticketSelectType.
  ///
  /// In en, this message translates to:
  /// **'Select Type'**
  String get ticketSelectType;

  /// No description provided for @ticketAttachPhotos.
  ///
  /// In en, this message translates to:
  /// **'Attach Photos'**
  String get ticketAttachPhotos;

  /// No description provided for @ticketAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get ticketAttachments;

  /// No description provided for @ticketLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading ticket...'**
  String get ticketLoading;

  /// No description provided for @ticketLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load ticket'**
  String get ticketLoadFailed;

  /// No description provided for @ticketNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get ticketNoMessages;

  /// No description provided for @ticketStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Send a message to start the conversation'**
  String get ticketStartConversation;

  /// No description provided for @ticketTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get ticketTypeMessage;

  /// No description provided for @ticketOptions.
  ///
  /// In en, this message translates to:
  /// **'Ticket Options'**
  String get ticketOptions;

  /// No description provided for @ticketRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh Ticket'**
  String get ticketRefresh;

  /// No description provided for @ticketShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show Details'**
  String get ticketShowDetails;

  /// No description provided for @ticketHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide Details'**
  String get ticketHideDetails;

  /// No description provided for @ticketCopyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy Ticket Number'**
  String get ticketCopyNumber;

  /// No description provided for @ticketCallEngineer.
  ///
  /// In en, this message translates to:
  /// **'Call Engineer'**
  String get ticketCallEngineer;

  /// No description provided for @ticketCallSupport.
  ///
  /// In en, this message translates to:
  /// **'Call iFrontiers Support'**
  String get ticketCallSupport;

  /// No description provided for @ticketClose.
  ///
  /// In en, this message translates to:
  /// **'Close Ticket'**
  String get ticketClose;

  /// No description provided for @ticketReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen Ticket'**
  String get ticketReopen;

  /// No description provided for @ticketAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach Image'**
  String get ticketAttachImage;

  /// No description provided for @ticketCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get ticketCamera;

  /// No description provided for @ticketGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get ticketGallery;

  /// No description provided for @ticketRateExperience.
  ///
  /// In en, this message translates to:
  /// **'How was your experience?'**
  String get ticketRateExperience;

  /// No description provided for @ticketRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rate our support to help us improve'**
  String get ticketRateSubtitle;

  /// No description provided for @ticketRateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate Your Experience'**
  String get ticketRateTitle;

  /// No description provided for @ticketFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Share your feedback (optional)'**
  String get ticketFeedbackHint;

  /// No description provided for @ticketSubmitRating.
  ///
  /// In en, this message translates to:
  /// **'Submit Rating'**
  String get ticketSubmitRating;

  /// No description provided for @ticketOrderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get ticketOrderDetails;

  /// No description provided for @ticketConversationEnded.
  ///
  /// In en, this message translates to:
  /// **'This conversation has ended'**
  String get ticketConversationEnded;

  /// No description provided for @ticketSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Ticket'**
  String get ticketSubmit;

  /// No description provided for @ticketChooseMachineHint.
  ///
  /// In en, this message translates to:
  /// **'Choose your machine'**
  String get ticketChooseMachineHint;

  /// No description provided for @ticketSubjectRequired.
  ///
  /// In en, this message translates to:
  /// **'Subject is required'**
  String get ticketSubjectRequired;

  /// No description provided for @ticketDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description is required'**
  String get ticketDescriptionRequired;

  /// No description provided for @ticketCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Support ticket created!'**
  String get ticketCreatedSuccess;

  /// No description provided for @inquiryCreateNew.
  ///
  /// In en, this message translates to:
  /// **'New Inquiry'**
  String get inquiryCreateNew;

  /// No description provided for @inquirySubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Inquiry'**
  String get inquirySubmit;

  /// No description provided for @inquirySubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Inquiry submitted!'**
  String get inquirySubmittedSuccess;

  /// No description provided for @ticketSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get ticketSubmitting;

  /// No description provided for @ticketSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Ticket submitted successfully'**
  String get ticketSubmitted;

  /// No description provided for @ticketNoTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get ticketNoTickets;

  /// No description provided for @ticketNoTicketsDesc.
  ///
  /// In en, this message translates to:
  /// **'Your support tickets will appear here'**
  String get ticketNoTicketsDesc;

  /// No description provided for @ticketAssignedTo.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get ticketAssignedTo;

  /// No description provided for @ticketUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get ticketUnassigned;

  /// No description provided for @ticketCreatedOn.
  ///
  /// In en, this message translates to:
  /// **'Created on'**
  String get ticketCreatedOn;

  /// No description provided for @ticketLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get ticketLastUpdated;

  /// No description provided for @ticketDealValue.
  ///
  /// In en, this message translates to:
  /// **'Deal Value'**
  String get ticketDealValue;

  /// No description provided for @ticketQuoteAmount.
  ///
  /// In en, this message translates to:
  /// **'Quote Amount'**
  String get ticketQuoteAmount;

  /// No description provided for @ticketFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-up Date'**
  String get ticketFollowUp;

  /// No description provided for @ticketEstimatedResolution.
  ///
  /// In en, this message translates to:
  /// **'Estimated Resolution'**
  String get ticketEstimatedResolution;

  /// No description provided for @ticketSalesStage.
  ///
  /// In en, this message translates to:
  /// **'Sales Stage'**
  String get ticketSalesStage;

  /// No description provided for @ticketHotLead.
  ///
  /// In en, this message translates to:
  /// **'Hot Lead'**
  String get ticketHotLead;

  /// No description provided for @ticketReopened.
  ///
  /// In en, this message translates to:
  /// **'Reopened'**
  String get ticketReopened;

  /// No description provided for @ticketEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get ticketEscalated;

  /// No description provided for @ticketEscalationReason.
  ///
  /// In en, this message translates to:
  /// **'Escalation Reason'**
  String get ticketEscalationReason;

  /// No description provided for @ticketQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get ticketQuantity;

  /// No description provided for @ticketDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address'**
  String get ticketDeliveryAddress;

  /// No description provided for @ticketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get ticketStatusOpen;

  /// No description provided for @ticketStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get ticketStatusInProgress;

  /// No description provided for @ticketStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get ticketStatusResolved;

  /// No description provided for @ticketStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get ticketStatusClosed;

  /// No description provided for @ticketStatusEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get ticketStatusEscalated;

  /// No description provided for @ticketStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get ticketStatusPending;

  /// No description provided for @ticketStatusOnHold.
  ///
  /// In en, this message translates to:
  /// **'On Hold'**
  String get ticketStatusOnHold;

  /// No description provided for @ticketFilterAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get ticketFilterAssigned;

  /// No description provided for @ticketFilterWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get ticketFilterWorking;

  /// No description provided for @ticketFilterWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get ticketFilterWaiting;

  /// No description provided for @ticketNoSupport.
  ///
  /// In en, this message translates to:
  /// **'No Support Tickets'**
  String get ticketNoSupport;

  /// No description provided for @ticketNoInquiries.
  ///
  /// In en, this message translates to:
  /// **'No Inquiries Yet'**
  String get ticketNoInquiries;

  /// No description provided for @ticketNewTicket.
  ///
  /// In en, this message translates to:
  /// **'New Ticket'**
  String get ticketNewTicket;

  /// No description provided for @ticketNoSupportDesc.
  ///
  /// In en, this message translates to:
  /// **'Need help with your machine?\nCreate a support ticket.'**
  String get ticketNoSupportDesc;

  /// No description provided for @ticketNoInquiriesDesc.
  ///
  /// In en, this message translates to:
  /// **'Interested in a new machine?\nBrowse our catalog.'**
  String get ticketNoInquiriesDesc;

  /// No description provided for @ticketPriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get ticketPriorityLow;

  /// No description provided for @ticketPriorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get ticketPriorityMedium;

  /// No description provided for @ticketPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get ticketPriorityHigh;

  /// No description provided for @ticketPriorityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get ticketPriorityCritical;

  /// No description provided for @ticketTypeSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get ticketTypeSupport;

  /// No description provided for @ticketTypeInquiry.
  ///
  /// In en, this message translates to:
  /// **'Inquiry'**
  String get ticketTypeInquiry;

  /// No description provided for @ticketTypeMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get ticketTypeMaintenance;

  /// No description provided for @ticketTypeComplaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get ticketTypeComplaint;

  /// No description provided for @ticketCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get ticketCategoryGeneral;

  /// No description provided for @ticketCategoryTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get ticketCategoryTechnical;

  /// No description provided for @ticketCategoryBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get ticketCategoryBilling;

  /// No description provided for @ticketCategorySales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get ticketCategorySales;

  /// No description provided for @chatTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get chatTypeMessage;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatSending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get chatSending;

  /// No description provided for @chatAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get chatAttachment;

  /// No description provided for @chatAddAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add Attachment'**
  String get chatAddAttachment;

  /// No description provided for @chatInternalNote.
  ///
  /// In en, this message translates to:
  /// **'Internal Note'**
  String get chatInternalNote;

  /// No description provided for @chatInternalNoteHint.
  ///
  /// In en, this message translates to:
  /// **'This note is only visible to staff'**
  String get chatInternalNoteHint;

  /// No description provided for @chatInternalBanner.
  ///
  /// In en, this message translates to:
  /// **'Internal note — not visible to customer'**
  String get chatInternalBanner;

  /// No description provided for @chatNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatNoMessages;

  /// No description provided for @chatStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Start the conversation'**
  String get chatStartConversation;

  /// No description provided for @chatLoadEarlier.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get chatLoadEarlier;

  /// No description provided for @chatNewMessage.
  ///
  /// In en, this message translates to:
  /// **'New Message'**
  String get chatNewMessage;

  /// No description provided for @chatYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatYou;

  /// No description provided for @chatAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get chatAdmin;

  /// No description provided for @chatEngineer.
  ///
  /// In en, this message translates to:
  /// **'Engineer'**
  String get chatEngineer;

  /// No description provided for @chatCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get chatCustomer;

  /// No description provided for @chatImageSent.
  ///
  /// In en, this message translates to:
  /// **'Image sent'**
  String get chatImageSent;

  /// No description provided for @chatQuickReplies.
  ///
  /// In en, this message translates to:
  /// **'Quick Replies'**
  String get chatQuickReplies;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @profileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEdit;

  /// No description provided for @profileChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get profileChangePhoto;

  /// No description provided for @profileRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get profileRemovePhoto;

  /// No description provided for @profilePersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get profilePersonalInfo;

  /// No description provided for @profileContactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact Information'**
  String get profileContactInfo;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// No description provided for @profileDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get profileDarkMode;

  /// No description provided for @profileLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profileLanguage;

  /// No description provided for @profileNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileNotifications;

  /// No description provided for @profileAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileAbout;

  /// No description provided for @profileVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String profileVersion(String version);

  /// No description provided for @profileUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get profileUpdate;

  /// No description provided for @profileUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get profileUpdating;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdated;

  /// No description provided for @profileBio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get profileBio;

  /// No description provided for @profileSpecializations.
  ///
  /// In en, this message translates to:
  /// **'Specializations'**
  String get profileSpecializations;

  /// No description provided for @profileAvailability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get profileAvailability;

  /// No description provided for @profileAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get profileAvailable;

  /// No description provided for @profileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get profileUnavailable;

  /// No description provided for @profileBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get profileBusy;

  /// No description provided for @profileCompletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Profile'**
  String get profileCompletionTitle;

  /// No description provided for @profileCompletionDesc.
  ///
  /// In en, this message translates to:
  /// **'Fill in all fields to earn 100 bonus points!'**
  String get profileCompletionDesc;

  /// No description provided for @profileLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading profile...'**
  String get profileLoading;

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to Load Profile'**
  String get profileLoadFailed;

  /// No description provided for @profileEngagementProgress.
  ///
  /// In en, this message translates to:
  /// **'Engagement Progress'**
  String get profileEngagementProgress;

  /// No description provided for @profileAccountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account Information'**
  String get profileAccountInfo;

  /// No description provided for @profileQuickNav.
  ///
  /// In en, this message translates to:
  /// **'Quick Navigation'**
  String get profileQuickNav;

  /// No description provided for @profileMyDocuments.
  ///
  /// In en, this message translates to:
  /// **'My Documents'**
  String get profileMyDocuments;

  /// No description provided for @profileMyInvoices.
  ///
  /// In en, this message translates to:
  /// **'My Invoices'**
  String get profileMyInvoices;

  /// No description provided for @profileMyInvoicesDesc.
  ///
  /// In en, this message translates to:
  /// **'View, download and pay invoices'**
  String get profileMyInvoicesDesc;

  /// No description provided for @profileMyQuotations.
  ///
  /// In en, this message translates to:
  /// **'My Quotations'**
  String get profileMyQuotations;

  /// No description provided for @profileMyQuotationsDesc.
  ///
  /// In en, this message translates to:
  /// **'View pending and accepted quotes'**
  String get profileMyQuotationsDesc;

  /// No description provided for @profileMyInstallments.
  ///
  /// In en, this message translates to:
  /// **'My Installments'**
  String get profileMyInstallments;

  /// No description provided for @profileMyInstallmentsDesc.
  ///
  /// In en, this message translates to:
  /// **'Track payments and upload receipts'**
  String get profileMyInstallmentsDesc;

  /// No description provided for @profileContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact & Support'**
  String get profileContactSupport;

  /// No description provided for @profileAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get profileAppearance;

  /// No description provided for @profileSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get profileSaveChanges;

  /// No description provided for @profileDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get profileDark;

  /// No description provided for @profileLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get profileLight;

  /// No description provided for @profileProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get profileProvince;

  /// No description provided for @profileDistrict.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get profileDistrict;

  /// No description provided for @profileSelectDistrict.
  ///
  /// In en, this message translates to:
  /// **'Select district'**
  String get profileSelectDistrict;

  /// No description provided for @profileDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes?'**
  String get profileDiscardChanges;

  /// No description provided for @profileKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep Editing'**
  String get profileKeepEditing;

  /// No description provided for @machineTitle.
  ///
  /// In en, this message translates to:
  /// **'My Machines'**
  String get machineTitle;

  /// No description provided for @machineRegister.
  ///
  /// In en, this message translates to:
  /// **'Register Machine'**
  String get machineRegister;

  /// No description provided for @machineRegisterNew.
  ///
  /// In en, this message translates to:
  /// **'Register New Machine'**
  String get machineRegisterNew;

  /// No description provided for @machineSerialNumber.
  ///
  /// In en, this message translates to:
  /// **'Serial Number'**
  String get machineSerialNumber;

  /// No description provided for @machineSerialHint.
  ///
  /// In en, this message translates to:
  /// **'Enter serial number'**
  String get machineSerialHint;

  /// No description provided for @machinePurchaseDate.
  ///
  /// In en, this message translates to:
  /// **'Purchase Date'**
  String get machinePurchaseDate;

  /// No description provided for @machineWarrantyEnd.
  ///
  /// In en, this message translates to:
  /// **'Warranty End Date'**
  String get machineWarrantyEnd;

  /// No description provided for @machineNextService.
  ///
  /// In en, this message translates to:
  /// **'Next Service Due'**
  String get machineNextService;

  /// No description provided for @machineInstallAddress.
  ///
  /// In en, this message translates to:
  /// **'Installation Address'**
  String get machineInstallAddress;

  /// No description provided for @machineStatus.
  ///
  /// In en, this message translates to:
  /// **'Machine Status'**
  String get machineStatus;

  /// No description provided for @machineActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get machineActive;

  /// No description provided for @machineInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get machineInactive;

  /// No description provided for @machineUnderRepair.
  ///
  /// In en, this message translates to:
  /// **'Under Repair'**
  String get machineUnderRepair;

  /// No description provided for @machineNoMachines.
  ///
  /// In en, this message translates to:
  /// **'No machines registered'**
  String get machineNoMachines;

  /// No description provided for @machineNoMachinesDesc.
  ///
  /// In en, this message translates to:
  /// **'Register your machines to track service history'**
  String get machineNoMachinesDesc;

  /// No description provided for @machineDetails.
  ///
  /// In en, this message translates to:
  /// **'Machine Details'**
  String get machineDetails;

  /// No description provided for @machineServiceHistory.
  ///
  /// In en, this message translates to:
  /// **'Service History'**
  String get machineServiceHistory;

  /// No description provided for @machineRegistered.
  ///
  /// In en, this message translates to:
  /// **'Machine registered successfully'**
  String get machineRegistered;

  /// No description provided for @machineRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering...'**
  String get machineRegistering;

  /// No description provided for @machinePurchaseInfo.
  ///
  /// In en, this message translates to:
  /// **'Purchase Information'**
  String get machinePurchaseInfo;

  /// No description provided for @machineWarrantyInfo.
  ///
  /// In en, this message translates to:
  /// **'Warranty Information'**
  String get machineWarrantyInfo;

  /// No description provided for @machineWarrantyActive.
  ///
  /// In en, this message translates to:
  /// **'Warranty Active'**
  String get machineWarrantyActive;

  /// No description provided for @machineWarrantyExpired.
  ///
  /// In en, this message translates to:
  /// **'Warranty Expired'**
  String get machineWarrantyExpired;

  /// No description provided for @machineInService.
  ///
  /// In en, this message translates to:
  /// **'In Service'**
  String get machineInService;

  /// No description provided for @machineViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get machineViewDetails;

  /// No description provided for @machineGetSupport.
  ///
  /// In en, this message translates to:
  /// **'Get Support'**
  String get machineGetSupport;

  /// No description provided for @machineViewManual.
  ///
  /// In en, this message translates to:
  /// **'View Manual'**
  String get machineViewManual;

  /// No description provided for @machineFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get machineFavorite;

  /// No description provided for @machineUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get machineUnfavorite;

  /// No description provided for @machineAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get machineAddFavorite;

  /// No description provided for @machineRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get machineRemoveFavorite;

  /// No description provided for @machineSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get machineSortBy;

  /// No description provided for @machineNoMachinesFound.
  ///
  /// In en, this message translates to:
  /// **'No Machines Found'**
  String get machineNoMachinesFound;

  /// No description provided for @machineClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get machineClearFilters;

  /// No description provided for @machineRegisterFirst.
  ///
  /// In en, this message translates to:
  /// **'Register First Machine'**
  String get machineRegisterFirst;

  /// No description provided for @machineLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your machines.\nPlease check your connection and try again.'**
  String get machineLoadError;

  /// No description provided for @machineNoMatchDesc.
  ///
  /// In en, this message translates to:
  /// **'No machines match your search or filter.\nTry adjusting your criteria.'**
  String get machineNoMatchDesc;

  /// No description provided for @machineRegisterDesc.
  ///
  /// In en, this message translates to:
  /// **'Register your iFrontiers machines\nto track service and get support.'**
  String get machineRegisterDesc;

  /// No description provided for @catalogPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get catalogPlaceOrder;

  /// No description provided for @machineInquire.
  ///
  /// In en, this message translates to:
  /// **'Inquire'**
  String get machineInquire;

  /// No description provided for @machineSubmitOrder.
  ///
  /// In en, this message translates to:
  /// **'Submit Order Request'**
  String get machineSubmitOrder;

  /// No description provided for @machineReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Our team will review and\nrespond within 24 hours.'**
  String get machineReviewNote;

  /// No description provided for @machineOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open Chat'**
  String get machineOpenChat;

  /// No description provided for @machineContinueBrowsing.
  ///
  /// In en, this message translates to:
  /// **'Continue Browsing'**
  String get machineContinueBrowsing;

  /// No description provided for @machineNoImage.
  ///
  /// In en, this message translates to:
  /// **'No image available'**
  String get machineNoImage;

  /// No description provided for @machineYouOwn.
  ///
  /// In en, this message translates to:
  /// **'You own this machine'**
  String get machineYouOwn;

  /// No description provided for @machineQuoteHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to get a personalized quote'**
  String get machineQuoteHint;

  /// No description provided for @machineNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need Help Choosing?'**
  String get machineNeedHelp;

  /// No description provided for @machineExpertsGuide.
  ///
  /// In en, this message translates to:
  /// **'Our experts can guide you'**
  String get machineExpertsGuide;

  /// No description provided for @machineCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get machineCall;

  /// No description provided for @registerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search machines by name, brand, model...'**
  String get registerSearchHint;

  /// No description provided for @registerSelectMachine.
  ///
  /// In en, this message translates to:
  /// **'Select a Machine'**
  String get registerSelectMachine;

  /// No description provided for @registerSelectPurchaseDate.
  ///
  /// In en, this message translates to:
  /// **'Select purchase date'**
  String get registerSelectPurchaseDate;

  /// No description provided for @registerSelectWarrantyDate.
  ///
  /// In en, this message translates to:
  /// **'Select warranty end date'**
  String get registerSelectWarrantyDate;

  /// No description provided for @registerChooseConnector.
  ///
  /// In en, this message translates to:
  /// **'Choose your connector'**
  String get registerChooseConnector;

  /// No description provided for @registerConnectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Marketers and admins who can contact you'**
  String get registerConnectorDesc;

  /// No description provided for @registerDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get registerDiscard;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportTitle;

  /// No description provided for @supportCenter.
  ///
  /// In en, this message translates to:
  /// **'Support Center'**
  String get supportCenter;

  /// No description provided for @supportHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportHowCanWeHelp;

  /// No description provided for @supportChooseOption.
  ///
  /// In en, this message translates to:
  /// **'Choose an option below to get started'**
  String get supportChooseOption;

  /// No description provided for @supportTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical Support'**
  String get supportTechnical;

  /// No description provided for @supportTechnicalDesc.
  ///
  /// In en, this message translates to:
  /// **'Machine issues, maintenance & troubleshooting'**
  String get supportTechnicalDesc;

  /// No description provided for @supportGeneralInquiry.
  ///
  /// In en, this message translates to:
  /// **'General Inquiry'**
  String get supportGeneralInquiry;

  /// No description provided for @supportGeneralInquiryDesc.
  ///
  /// In en, this message translates to:
  /// **'Product info, pricing & availability questions'**
  String get supportGeneralInquiryDesc;

  /// No description provided for @supportPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place an Order'**
  String get supportPlaceOrder;

  /// No description provided for @supportPlaceOrderDesc.
  ///
  /// In en, this message translates to:
  /// **'Order machines, parts or consumables'**
  String get supportPlaceOrderDesc;

  /// No description provided for @supportMySchedules.
  ///
  /// In en, this message translates to:
  /// **'My Schedules'**
  String get supportMySchedules;

  /// No description provided for @supportMySchedulesDesc.
  ///
  /// In en, this message translates to:
  /// **'View and request service visits'**
  String get supportMySchedulesDesc;

  /// No description provided for @supportRecentTickets.
  ///
  /// In en, this message translates to:
  /// **'Recent Tickets'**
  String get supportRecentTickets;

  /// No description provided for @supportOptions.
  ///
  /// In en, this message translates to:
  /// **'Support Options'**
  String get supportOptions;

  /// No description provided for @supportCreateTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Support Ticket'**
  String get supportCreateTicket;

  /// No description provided for @supportTrackTickets.
  ///
  /// In en, this message translates to:
  /// **'Track Tickets'**
  String get supportTrackTickets;

  /// No description provided for @supportKnowledgeBase.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get supportKnowledgeBase;

  /// No description provided for @supportMyMachines.
  ///
  /// In en, this message translates to:
  /// **'My Machines'**
  String get supportMyMachines;

  /// No description provided for @supportFaqs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get supportFaqs;

  /// No description provided for @supportContactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get supportContactUs;

  /// No description provided for @supportCallUs.
  ///
  /// In en, this message translates to:
  /// **'Call Us'**
  String get supportCallUs;

  /// No description provided for @supportEmailUs.
  ///
  /// In en, this message translates to:
  /// **'Email Us'**
  String get supportEmailUs;

  /// No description provided for @supportRequestService.
  ///
  /// In en, this message translates to:
  /// **'Request Service'**
  String get supportRequestService;

  /// No description provided for @supportOrderMachine.
  ///
  /// In en, this message translates to:
  /// **'Order a Machine'**
  String get supportOrderMachine;

  /// No description provided for @supportViewSchedule.
  ///
  /// In en, this message translates to:
  /// **'View Schedule'**
  String get supportViewSchedule;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'My Schedules'**
  String get scheduleTitle;

  /// No description provided for @scheduleUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get scheduleUpcoming;

  /// No description provided for @schedulePast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get schedulePast;

  /// No description provided for @scheduleToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get scheduleToday;

  /// No description provided for @scheduleTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get scheduleTomorrow;

  /// No description provided for @scheduleRequestService.
  ///
  /// In en, this message translates to:
  /// **'Request Service'**
  String get scheduleRequestService;

  /// No description provided for @scheduleServiceType.
  ///
  /// In en, this message translates to:
  /// **'Service Type'**
  String get scheduleServiceType;

  /// No description provided for @scheduleSelectType.
  ///
  /// In en, this message translates to:
  /// **'Select Service Type'**
  String get scheduleSelectType;

  /// No description provided for @scheduleDate.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Date'**
  String get scheduleDate;

  /// No description provided for @scheduleTime.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Time'**
  String get scheduleTime;

  /// No description provided for @scheduleDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get scheduleDuration;

  /// No description provided for @scheduleDurationMin.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String scheduleDurationMin(int minutes);

  /// No description provided for @scheduleLocation.
  ///
  /// In en, this message translates to:
  /// **'Service Location'**
  String get scheduleLocation;

  /// No description provided for @scheduleEngineer.
  ///
  /// In en, this message translates to:
  /// **'Engineer'**
  String get scheduleEngineer;

  /// No description provided for @scheduleMachine.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get scheduleMachine;

  /// No description provided for @scheduleSelectMachine.
  ///
  /// In en, this message translates to:
  /// **'Select Machine'**
  String get scheduleSelectMachine;

  /// No description provided for @scheduleSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get scheduleSelectDate;

  /// No description provided for @scheduleSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select Time'**
  String get scheduleSelectTime;

  /// No description provided for @scheduleDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get scheduleDescription;

  /// No description provided for @scheduleDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what service you need...'**
  String get scheduleDescriptionHint;

  /// No description provided for @scheduleCustomerNotes.
  ///
  /// In en, this message translates to:
  /// **'Customer Notes'**
  String get scheduleCustomerNotes;

  /// No description provided for @scheduleAdminNotes.
  ///
  /// In en, this message translates to:
  /// **'Admin Notes'**
  String get scheduleAdminNotes;

  /// No description provided for @scheduleEngineerNotes.
  ///
  /// In en, this message translates to:
  /// **'Engineer Notes'**
  String get scheduleEngineerNotes;

  /// No description provided for @scheduleServiceReport.
  ///
  /// In en, this message translates to:
  /// **'Service Report'**
  String get scheduleServiceReport;

  /// No description provided for @scheduleRateService.
  ///
  /// In en, this message translates to:
  /// **'Rate Service'**
  String get scheduleRateService;

  /// No description provided for @scheduleRateTitle.
  ///
  /// In en, this message translates to:
  /// **'How was the service?'**
  String get scheduleRateTitle;

  /// No description provided for @scheduleSubmitRating.
  ///
  /// In en, this message translates to:
  /// **'Submit Rating'**
  String get scheduleSubmitRating;

  /// No description provided for @scheduleRatingSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Rating submitted. Thank you!'**
  String get scheduleRatingSubmitted;

  /// No description provided for @scheduleFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Share your experience (optional)...'**
  String get scheduleFeedbackHint;

  /// No description provided for @scheduleCancelSchedule.
  ///
  /// In en, this message translates to:
  /// **'Cancel Schedule'**
  String get scheduleCancelSchedule;

  /// No description provided for @scheduleReschedule.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get scheduleReschedule;

  /// No description provided for @scheduleCancelReason.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Reason'**
  String get scheduleCancelReason;

  /// No description provided for @scheduleCancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why are you cancelling?'**
  String get scheduleCancelReasonHint;

  /// No description provided for @scheduleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Schedule cancelled'**
  String get scheduleCancelled;

  /// No description provided for @scheduleRescheduled.
  ///
  /// In en, this message translates to:
  /// **'Schedule rescheduled'**
  String get scheduleRescheduled;

  /// No description provided for @scheduleConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Schedule confirmed'**
  String get scheduleConfirmed;

  /// No description provided for @scheduleNoUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No upcoming schedules'**
  String get scheduleNoUpcoming;

  /// No description provided for @scheduleNoUpcomingDesc.
  ///
  /// In en, this message translates to:
  /// **'Your upcoming service appointments will appear here'**
  String get scheduleNoUpcomingDesc;

  /// No description provided for @scheduleNoPast.
  ///
  /// In en, this message translates to:
  /// **'No past schedules'**
  String get scheduleNoPast;

  /// No description provided for @scheduleNoPastDesc.
  ///
  /// In en, this message translates to:
  /// **'Your completed services will appear here'**
  String get scheduleNoPastDesc;

  /// No description provided for @scheduleRequestSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Service request submitted'**
  String get scheduleRequestSubmitted;

  /// No description provided for @scheduleSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get scheduleSubmitting;

  /// No description provided for @scheduleUseMachineAddress.
  ///
  /// In en, this message translates to:
  /// **'Use machine address'**
  String get scheduleUseMachineAddress;

  /// No description provided for @scheduleEstimatedDuration.
  ///
  /// In en, this message translates to:
  /// **'Estimated Duration'**
  String get scheduleEstimatedDuration;

  /// No description provided for @scheduleRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get scheduleRecurring;

  /// No description provided for @scheduleRecurrenceRule.
  ///
  /// In en, this message translates to:
  /// **'Recurrence'**
  String get scheduleRecurrenceRule;

  /// No description provided for @scheduleMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get scheduleMonthly;

  /// No description provided for @scheduleQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get scheduleQuarterly;

  /// No description provided for @scheduleBiannual.
  ///
  /// In en, this message translates to:
  /// **'Every 6 Months'**
  String get scheduleBiannual;

  /// No description provided for @scheduleAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get scheduleAnnual;

  /// No description provided for @scheduleCountdownToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get scheduleCountdownToday;

  /// No description provided for @scheduleCountdownTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get scheduleCountdownTomorrow;

  /// No description provided for @scheduleCountdownDays.
  ///
  /// In en, this message translates to:
  /// **'In {days} days'**
  String scheduleCountdownDays(int days);

  /// No description provided for @scheduleCountdownDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String scheduleCountdownDaysAgo(int days);

  /// No description provided for @scheduleTypePreventive.
  ///
  /// In en, this message translates to:
  /// **'Preventive Maintenance'**
  String get scheduleTypePreventive;

  /// No description provided for @scheduleTypeRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get scheduleTypeRepair;

  /// No description provided for @scheduleTypeInspection.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get scheduleTypeInspection;

  /// No description provided for @scheduleTypeInstallation.
  ///
  /// In en, this message translates to:
  /// **'Installation'**
  String get scheduleTypeInstallation;

  /// No description provided for @scheduleTypeWarrantyVisit.
  ///
  /// In en, this message translates to:
  /// **'Warranty Visit'**
  String get scheduleTypeWarrantyVisit;

  /// No description provided for @scheduleStatusRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get scheduleStatusRequested;

  /// No description provided for @scheduleStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduleStatusScheduled;

  /// No description provided for @scheduleStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get scheduleStatusConfirmed;

  /// No description provided for @scheduleStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get scheduleStatusInProgress;

  /// No description provided for @scheduleStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get scheduleStatusCompleted;

  /// No description provided for @scheduleStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get scheduleStatusCancelled;

  /// No description provided for @scheduleStatusRescheduled.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled'**
  String get scheduleStatusRescheduled;

  /// No description provided for @scheduleNoMachines.
  ///
  /// In en, this message translates to:
  /// **'No registered machines found'**
  String get scheduleNoMachines;

  /// No description provided for @scheduleLocationHint.
  ///
  /// In en, this message translates to:
  /// **'Enter service location'**
  String get scheduleLocationHint;

  /// No description provided for @scheduleCustomerNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Any notes for the service team...'**
  String get scheduleCustomerNotesHint;

  /// No description provided for @scheduleAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get scheduleAllTypes;

  /// No description provided for @requestServiceInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Submit your preferred date and time. Our team will confirm and assign an engineer.'**
  String get requestServiceInfoBanner;

  /// No description provided for @requestServiceWhatNeed.
  ///
  /// In en, this message translates to:
  /// **'What do you need?'**
  String get requestServiceWhatNeed;

  /// No description provided for @requestServiceTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get requestServiceTitleLabel;

  /// No description provided for @requestServiceTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Machine not starting'**
  String get requestServiceTitleHint;

  /// No description provided for @requestServiceTitleValidator.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title'**
  String get requestServiceTitleValidator;

  /// No description provided for @requestServiceSelectMachineOptional.
  ///
  /// In en, this message translates to:
  /// **'Select Machine (Optional)'**
  String get requestServiceSelectMachineOptional;

  /// No description provided for @requestServicePreferredDateTime.
  ///
  /// In en, this message translates to:
  /// **'Preferred Date & Time'**
  String get requestServicePreferredDateTime;

  /// No description provided for @requestServiceAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Address for the service visit'**
  String get requestServiceAddressHint;

  /// No description provided for @requestServiceUseInstallAddress.
  ///
  /// In en, this message translates to:
  /// **'Use machine installation address'**
  String get requestServiceUseInstallAddress;

  /// No description provided for @requestServiceAdditionalNotes.
  ///
  /// In en, this message translates to:
  /// **'Additional Notes'**
  String get requestServiceAdditionalNotes;

  /// No description provided for @requestServiceDescHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue or service needed...'**
  String get requestServiceDescHint;

  /// No description provided for @requestServiceNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Any special requirements or access instructions...'**
  String get requestServiceNotesHint;

  /// No description provided for @requestServiceSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get requestServiceSubmitting;

  /// No description provided for @requestServiceSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit Request'**
  String get requestServiceSubmitButton;

  /// No description provided for @requestServiceNoRegisteredMachines.
  ///
  /// In en, this message translates to:
  /// **'No registered machines. You can still request service.'**
  String get requestServiceNoRegisteredMachines;

  /// No description provided for @requestServiceFailedToSubmit.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit: {error}'**
  String requestServiceFailedToSubmit(String error);

  /// No description provided for @requestServiceMachineFallback.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get requestServiceMachineFallback;

  /// No description provided for @requestServiceModelSerial.
  ///
  /// In en, this message translates to:
  /// **'{model} · S/N: {serial}'**
  String requestServiceModelSerial(String model, String serial);

  /// No description provided for @scheduleNewSchedule.
  ///
  /// In en, this message translates to:
  /// **'New Schedule'**
  String get scheduleNewSchedule;

  /// No description provided for @scheduleScheduleDetail.
  ///
  /// In en, this message translates to:
  /// **'Schedule Detail'**
  String get scheduleScheduleDetail;

  /// No description provided for @scheduleCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get scheduleCreatedBy;

  /// No description provided for @scheduleLinkedTicket.
  ///
  /// In en, this message translates to:
  /// **'Linked Ticket'**
  String get scheduleLinkedTicket;

  /// No description provided for @scheduleCompleteService.
  ///
  /// In en, this message translates to:
  /// **'Complete Service'**
  String get scheduleCompleteService;

  /// No description provided for @scheduleReportRequired.
  ///
  /// In en, this message translates to:
  /// **'Service report is required to complete'**
  String get scheduleReportRequired;

  /// No description provided for @scheduleWriteReport.
  ///
  /// In en, this message translates to:
  /// **'Write Service Report'**
  String get scheduleWriteReport;

  /// No description provided for @scheduleReportHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the work performed, parts used, findings...'**
  String get scheduleReportHint;

  /// No description provided for @scheduleDeleteSchedule.
  ///
  /// In en, this message translates to:
  /// **'Delete Schedule'**
  String get scheduleDeleteSchedule;

  /// No description provided for @scheduleDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this schedule?'**
  String get scheduleDeleteConfirm;

  /// No description provided for @scheduleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Schedule deleted'**
  String get scheduleDeleted;

  /// No description provided for @scheduleNewDate.
  ///
  /// In en, this message translates to:
  /// **'New Date'**
  String get scheduleNewDate;

  /// No description provided for @scheduleNewTime.
  ///
  /// In en, this message translates to:
  /// **'New Time'**
  String get scheduleNewTime;

  /// No description provided for @scheduleRescheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm Reschedule'**
  String get scheduleRescheduleConfirm;

  /// No description provided for @invoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get invoiceTitle;

  /// No description provided for @invoiceMyInvoices.
  ///
  /// In en, this message translates to:
  /// **'My Invoices'**
  String get invoiceMyInvoices;

  /// No description provided for @invoiceCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Invoice'**
  String get invoiceCreate;

  /// No description provided for @invoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice #{number}'**
  String invoiceNumber(String number);

  /// No description provided for @invoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice Date'**
  String get invoiceDate;

  /// No description provided for @invoiceDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get invoiceDueDate;

  /// No description provided for @invoiceItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get invoiceItems;

  /// No description provided for @invoiceAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get invoiceAddItem;

  /// No description provided for @invoiceRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove Item'**
  String get invoiceRemoveItem;

  /// No description provided for @invoiceItemName.
  ///
  /// In en, this message translates to:
  /// **'Item Name'**
  String get invoiceItemName;

  /// No description provided for @invoiceItemDesc.
  ///
  /// In en, this message translates to:
  /// **'Item Description'**
  String get invoiceItemDesc;

  /// No description provided for @invoiceUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get invoiceUnitPrice;

  /// No description provided for @invoiceQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get invoiceQuantity;

  /// No description provided for @invoiceLineTotal.
  ///
  /// In en, this message translates to:
  /// **'Line Total'**
  String get invoiceLineTotal;

  /// No description provided for @invoiceSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get invoiceSubtotal;

  /// No description provided for @invoiceTaxRate.
  ///
  /// In en, this message translates to:
  /// **'Tax Rate'**
  String get invoiceTaxRate;

  /// No description provided for @invoiceTaxAmount.
  ///
  /// In en, this message translates to:
  /// **'Tax Amount'**
  String get invoiceTaxAmount;

  /// No description provided for @invoiceDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get invoiceDiscount;

  /// No description provided for @invoiceGrandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get invoiceGrandTotal;

  /// No description provided for @invoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get invoiceNotes;

  /// No description provided for @invoiceTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get invoiceTerms;

  /// No description provided for @invoiceSend.
  ///
  /// In en, this message translates to:
  /// **'Send Invoice'**
  String get invoiceSend;

  /// No description provided for @invoiceSending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get invoiceSending;

  /// No description provided for @invoiceSent.
  ///
  /// In en, this message translates to:
  /// **'Invoice sent'**
  String get invoiceSent;

  /// No description provided for @invoiceMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid'**
  String get invoiceMarkPaid;

  /// No description provided for @invoiceRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get invoiceRecordPayment;

  /// No description provided for @invoiceNoInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices'**
  String get invoiceNoInvoices;

  /// No description provided for @invoiceNoInvoicesDesc.
  ///
  /// In en, this message translates to:
  /// **'Your invoices will appear here'**
  String get invoiceNoInvoicesDesc;

  /// No description provided for @invoiceStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get invoiceStatusDraft;

  /// No description provided for @invoiceStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get invoiceStatusSent;

  /// No description provided for @invoiceStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get invoiceStatusPaid;

  /// No description provided for @invoiceStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially Paid'**
  String get invoiceStatusPartial;

  /// No description provided for @invoiceStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get invoiceStatusOverdue;

  /// No description provided for @invoiceStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get invoiceStatusCancelled;

  /// No description provided for @invoiceStatusVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get invoiceStatusVoid;

  /// No description provided for @invoiceStatusViewed.
  ///
  /// In en, this message translates to:
  /// **'Viewed'**
  String get invoiceStatusViewed;

  /// No description provided for @invoiceStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get invoiceStatusRefunded;

  /// No description provided for @invoiceStatusPartialShort.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get invoiceStatusPartialShort;

  /// No description provided for @invoiceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load invoices'**
  String get invoiceLoadFailed;

  /// No description provided for @invoiceBalanceAmount.
  ///
  /// In en, this message translates to:
  /// **'Balance: {amount}'**
  String invoiceBalanceAmount(String amount);

  /// No description provided for @invoiceOverdueByDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Overdue by 1 day} other{Overdue by {days} days}}'**
  String invoiceOverdueByDays(int days);

  /// No description provided for @invoiceDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get invoiceDueToday;

  /// No description provided for @invoiceDueInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Due in 1 day} other{Due in {days} days}}'**
  String invoiceDueInDays(int days);

  /// No description provided for @invoiceNoInvoicesYet.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet'**
  String get invoiceNoInvoicesYet;

  /// No description provided for @invoiceFilterNoResults.
  ///
  /// In en, this message translates to:
  /// **'No {filter} invoices'**
  String invoiceFilterNoResults(String filter);

  /// No description provided for @invoiceBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Balance Due'**
  String get invoiceBalanceDue;

  /// No description provided for @invoiceTotalPaid.
  ///
  /// In en, this message translates to:
  /// **'Total Paid'**
  String get invoiceTotalPaid;

  /// No description provided for @invoiceSelectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get invoiceSelectCustomer;

  /// No description provided for @invoiceSelectTicket.
  ///
  /// In en, this message translates to:
  /// **'Select Ticket'**
  String get invoiceSelectTicket;

  /// No description provided for @invoiceCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating invoice...'**
  String get invoiceCreating;

  /// No description provided for @invoiceCreated.
  ///
  /// In en, this message translates to:
  /// **'Invoice created successfully'**
  String get invoiceCreated;

  /// No description provided for @invoiceDetail.
  ///
  /// In en, this message translates to:
  /// **'Invoice Detail'**
  String get invoiceDetail;

  /// No description provided for @invoiceBillTo.
  ///
  /// In en, this message translates to:
  /// **'Bill To'**
  String get invoiceBillTo;

  /// No description provided for @invoiceFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get invoiceFrom;

  /// No description provided for @invoicePaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get invoicePaymentHistory;

  /// No description provided for @quotationTitle.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get quotationTitle;

  /// No description provided for @quotationMyQuotations.
  ///
  /// In en, this message translates to:
  /// **'My Quotations'**
  String get quotationMyQuotations;

  /// No description provided for @quotationCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Quotation'**
  String get quotationCreate;

  /// No description provided for @quotationNumber.
  ///
  /// In en, this message translates to:
  /// **'Quote #{number}'**
  String quotationNumber(String number);

  /// No description provided for @quotationDate.
  ///
  /// In en, this message translates to:
  /// **'Quotation Date'**
  String get quotationDate;

  /// No description provided for @quotationValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid Until'**
  String get quotationValidUntil;

  /// No description provided for @quotationItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get quotationItems;

  /// No description provided for @quotationAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get quotationAddItem;

  /// No description provided for @quotationSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get quotationSubtotal;

  /// No description provided for @quotationTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get quotationTax;

  /// No description provided for @quotationTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get quotationTotal;

  /// No description provided for @quotationNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get quotationNotes;

  /// No description provided for @quotationTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get quotationTerms;

  /// No description provided for @quotationSend.
  ///
  /// In en, this message translates to:
  /// **'Send Quotation'**
  String get quotationSend;

  /// No description provided for @quotationSending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get quotationSending;

  /// No description provided for @quotationSent.
  ///
  /// In en, this message translates to:
  /// **'Quotation sent'**
  String get quotationSent;

  /// No description provided for @quotationConvertToInvoice.
  ///
  /// In en, this message translates to:
  /// **'Convert to Invoice'**
  String get quotationConvertToInvoice;

  /// No description provided for @quotationNoQuotations.
  ///
  /// In en, this message translates to:
  /// **'No quotations'**
  String get quotationNoQuotations;

  /// No description provided for @quotationNoQuotationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Your quotations will appear here'**
  String get quotationNoQuotationsDesc;

  /// No description provided for @quotationStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get quotationStatusDraft;

  /// No description provided for @quotationStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get quotationStatusSent;

  /// No description provided for @quotationStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get quotationStatusAccepted;

  /// No description provided for @quotationStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get quotationStatusRejected;

  /// No description provided for @quotationStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get quotationStatusExpired;

  /// No description provided for @quotationStatusConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get quotationStatusConverted;

  /// No description provided for @quotationDetail.
  ///
  /// In en, this message translates to:
  /// **'Quotation Detail'**
  String get quotationDetail;

  /// No description provided for @quotationCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating quotation...'**
  String get quotationCreating;

  /// No description provided for @quotationCreated.
  ///
  /// In en, this message translates to:
  /// **'Quotation created successfully'**
  String get quotationCreated;

  /// No description provided for @quotationSelectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get quotationSelectCustomer;

  /// No description provided for @quotationSelectInquiry.
  ///
  /// In en, this message translates to:
  /// **'Select Inquiry'**
  String get quotationSelectInquiry;

  /// No description provided for @quotationAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get quotationAccept;

  /// No description provided for @quotationReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get quotationReject;

  /// No description provided for @quotationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load quotations'**
  String get quotationLoadFailed;

  /// No description provided for @quotationDetailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load details'**
  String get quotationDetailLoadFailed;

  /// No description provided for @quotationDates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get quotationDates;

  /// No description provided for @quotationSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get quotationSummary;

  /// No description provided for @quotationProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get quotationProcessing;

  /// No description provided for @quotationAcceptQuotation.
  ///
  /// In en, this message translates to:
  /// **'Accept Quotation'**
  String get quotationAcceptQuotation;

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentTitle;

  /// No description provided for @paymentDashboard.
  ///
  /// In en, this message translates to:
  /// **'Payment Dashboard'**
  String get paymentDashboard;

  /// No description provided for @paymentRecord.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get paymentRecord;

  /// No description provided for @paymentRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get paymentRecording;

  /// No description provided for @paymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get paymentRecorded;

  /// No description provided for @paymentAmount.
  ///
  /// In en, this message translates to:
  /// **'Payment Amount'**
  String get paymentAmount;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @paymentReference.
  ///
  /// In en, this message translates to:
  /// **'Payment Reference'**
  String get paymentReference;

  /// No description provided for @paymentReferenceHint.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID, cheque number, etc.'**
  String get paymentReferenceHint;

  /// No description provided for @paymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment Date'**
  String get paymentDate;

  /// No description provided for @paymentNotes.
  ///
  /// In en, this message translates to:
  /// **'Payment Notes'**
  String get paymentNotes;

  /// No description provided for @paymentNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Additional notes...'**
  String get paymentNotesHint;

  /// No description provided for @paymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Payment Received'**
  String get paymentReceived;

  /// No description provided for @paymentTotalReceived.
  ///
  /// In en, this message translates to:
  /// **'Total Received'**
  String get paymentTotalReceived;

  /// No description provided for @paymentTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total Outstanding'**
  String get paymentTotalOutstanding;

  /// No description provided for @paymentOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get paymentOverdue;

  /// No description provided for @paymentRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Payments'**
  String get paymentRecent;

  /// No description provided for @paymentNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded'**
  String get paymentNoPayments;

  /// No description provided for @paymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentMethodCash;

  /// No description provided for @paymentMethodBank.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get paymentMethodBank;

  /// No description provided for @paymentMethodCheque.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get paymentMethodCheque;

  /// No description provided for @paymentMethodCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentMethodCard;

  /// No description provided for @paymentMethodOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get paymentMethodOnline;

  /// No description provided for @paymentSummary.
  ///
  /// In en, this message translates to:
  /// **'Payment Summary'**
  String get paymentSummary;

  /// No description provided for @paymentAmountHint.
  ///
  /// In en, this message translates to:
  /// **'Enter amount'**
  String get paymentAmountHint;

  /// No description provided for @installmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get installmentTitle;

  /// No description provided for @installmentMyPlans.
  ///
  /// In en, this message translates to:
  /// **'My Installment Plans'**
  String get installmentMyPlans;

  /// No description provided for @installmentPlan.
  ///
  /// In en, this message translates to:
  /// **'Installment Plan'**
  String get installmentPlan;

  /// No description provided for @installmentTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get installmentTotalAmount;

  /// No description provided for @installmentDownPayment.
  ///
  /// In en, this message translates to:
  /// **'Down Payment'**
  String get installmentDownPayment;

  /// No description provided for @installmentMonthlyPayment.
  ///
  /// In en, this message translates to:
  /// **'Monthly Payment'**
  String get installmentMonthlyPayment;

  /// No description provided for @installmentNumInstallments.
  ///
  /// In en, this message translates to:
  /// **'Number of Installments'**
  String get installmentNumInstallments;

  /// No description provided for @installmentInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Interest Rate'**
  String get installmentInterestRate;

  /// No description provided for @installmentStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get installmentStartDate;

  /// No description provided for @installmentEndDate.
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get installmentEndDate;

  /// No description provided for @installmentNumber.
  ///
  /// In en, this message translates to:
  /// **'Installment {number} of {total}'**
  String installmentNumber(int number, int total);

  /// No description provided for @installmentDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get installmentDueDate;

  /// No description provided for @installmentAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get installmentAmount;

  /// No description provided for @installmentPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get installmentPaid;

  /// No description provided for @installmentPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get installmentPending;

  /// No description provided for @installmentOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get installmentOverdue;

  /// No description provided for @installmentTotalPaid.
  ///
  /// In en, this message translates to:
  /// **'Total Paid'**
  String get installmentTotalPaid;

  /// No description provided for @installmentTotalRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get installmentTotalRemaining;

  /// No description provided for @installmentNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next Due'**
  String get installmentNextDue;

  /// No description provided for @installmentNoPlans.
  ///
  /// In en, this message translates to:
  /// **'No installment plans'**
  String get installmentNoPlans;

  /// No description provided for @installmentNoPlansDesc.
  ///
  /// In en, this message translates to:
  /// **'Your installment plans will appear here'**
  String get installmentNoPlansDesc;

  /// No description provided for @installmentPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get installmentPaymentHistory;

  /// No description provided for @installmentMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid'**
  String get installmentMarkPaid;

  /// No description provided for @installmentPay.
  ///
  /// In en, this message translates to:
  /// **'Pay Installment'**
  String get installmentPay;

  /// No description provided for @installmentDetail.
  ///
  /// In en, this message translates to:
  /// **'Installment Detail'**
  String get installmentDetail;

  /// No description provided for @installmentProgress.
  ///
  /// In en, this message translates to:
  /// **'{paid} of {total} paid'**
  String installmentProgress(int paid, int total);

  /// No description provided for @installmentOnTime.
  ///
  /// In en, this message translates to:
  /// **'On Time'**
  String get installmentOnTime;

  /// No description provided for @installmentLate.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get installmentLate;

  /// No description provided for @installmentPaidBadge.
  ///
  /// In en, this message translates to:
  /// **'PAID'**
  String get installmentPaidBadge;

  /// No description provided for @installmentUnknownMachine.
  ///
  /// In en, this message translates to:
  /// **'Unknown Machine'**
  String get installmentUnknownMachine;

  /// No description provided for @installmentMyInstallments.
  ///
  /// In en, this message translates to:
  /// **'My Installments'**
  String get installmentMyInstallments;

  /// No description provided for @installmentSerialLabel.
  ///
  /// In en, this message translates to:
  /// **'SN: {serial}'**
  String installmentSerialLabel(String serial);

  /// No description provided for @installmentPaymentsCount.
  ///
  /// In en, this message translates to:
  /// **'{paid} / {total} payments'**
  String installmentPaymentsCount(int paid, int total);

  /// No description provided for @installmentPaymentsOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count} payment(s) overdue'**
  String installmentPaymentsOverdue(int count);

  /// No description provided for @installmentNextDueDetails.
  ///
  /// In en, this message translates to:
  /// **'Next due: {date} — {amount}'**
  String installmentNextDueDetails(String date, String amount);

  /// No description provided for @installmentNoPlansTitle.
  ///
  /// In en, this message translates to:
  /// **'No Installment Plans'**
  String get installmentNoPlansTitle;

  /// No description provided for @installmentNoPlansDescTwoLine.
  ///
  /// In en, this message translates to:
  /// **'Your installment plans will\nappear here when created.'**
  String get installmentNoPlansDescTwoLine;

  /// No description provided for @referralTitle.
  ///
  /// In en, this message translates to:
  /// **'Referral Program'**
  String get referralTitle;

  /// No description provided for @referralMyCode.
  ///
  /// In en, this message translates to:
  /// **'My Referral Code'**
  String get referralMyCode;

  /// No description provided for @referralShareCode.
  ///
  /// In en, this message translates to:
  /// **'Share Code'**
  String get referralShareCode;

  /// No description provided for @referralCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy Code'**
  String get referralCopyCode;

  /// No description provided for @referralCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Referral code copied!'**
  String get referralCodeCopied;

  /// No description provided for @referralHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get referralHowItWorks;

  /// No description provided for @referralReferEarn.
  ///
  /// In en, this message translates to:
  /// **'Refer & Earn'**
  String get referralReferEarn;

  /// No description provided for @referralTagline.
  ///
  /// In en, this message translates to:
  /// **'Invite friends, earn commissions'**
  String get referralTagline;

  /// No description provided for @referralHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends,\nEarn Commissions!'**
  String get referralHeroTitle;

  /// No description provided for @referralCommissionRates.
  ///
  /// In en, this message translates to:
  /// **'Commission Rates'**
  String get referralCommissionRates;

  /// No description provided for @referralMinPurchase.
  ///
  /// In en, this message translates to:
  /// **'Min purchase: {amount}'**
  String referralMinPurchase(String amount);

  /// No description provided for @referralStep1.
  ///
  /// In en, this message translates to:
  /// **'Share Your Code'**
  String get referralStep1;

  /// No description provided for @referralStep1Desc.
  ///
  /// In en, this message translates to:
  /// **'Share your unique referral code with friends and colleagues'**
  String get referralStep1Desc;

  /// No description provided for @referralStep2.
  ///
  /// In en, this message translates to:
  /// **'They Sign Up'**
  String get referralStep2;

  /// No description provided for @referralStep2Desc.
  ///
  /// In en, this message translates to:
  /// **'When they create an account using your code, you get notified'**
  String get referralStep2Desc;

  /// No description provided for @referralStep3.
  ///
  /// In en, this message translates to:
  /// **'Earn Rewards'**
  String get referralStep3;

  /// No description provided for @referralStep3Desc.
  ///
  /// In en, this message translates to:
  /// **'Once they make a qualifying purchase, you earn commission!'**
  String get referralStep3Desc;

  /// No description provided for @referralTotalReferrals.
  ///
  /// In en, this message translates to:
  /// **'Total Referrals'**
  String get referralTotalReferrals;

  /// No description provided for @referralQualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get referralQualified;

  /// No description provided for @referralPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get referralPending;

  /// No description provided for @referralEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get referralEarnings;

  /// No description provided for @referralTotalEarnings.
  ///
  /// In en, this message translates to:
  /// **'Total Earnings'**
  String get referralTotalEarnings;

  /// No description provided for @referralHistory.
  ///
  /// In en, this message translates to:
  /// **'Referral History'**
  String get referralHistory;

  /// No description provided for @referralNoReferrals.
  ///
  /// In en, this message translates to:
  /// **'No referrals yet'**
  String get referralNoReferrals;

  /// No description provided for @referralNoReferralsDesc.
  ///
  /// In en, this message translates to:
  /// **'Share your code to start earning rewards'**
  String get referralNoReferralsDesc;

  /// No description provided for @referralShareMessage.
  ///
  /// In en, this message translates to:
  /// **'Join i Connect with my referral code: {code}\nDownload the app and sign up to get started!'**
  String referralShareMessage(String code);

  /// No description provided for @referralStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get referralStatusPending;

  /// No description provided for @referralStatusSignedUp.
  ///
  /// In en, this message translates to:
  /// **'Signed Up'**
  String get referralStatusSignedUp;

  /// No description provided for @referralStatusCooling.
  ///
  /// In en, this message translates to:
  /// **'Cooling Period'**
  String get referralStatusCooling;

  /// No description provided for @referralStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get referralStatusApproved;

  /// No description provided for @referralStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get referralStatusPaid;

  /// No description provided for @referralStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get referralStatusExpired;

  /// No description provided for @referralStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get referralStatusRejected;

  /// No description provided for @referralCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get referralCommission;

  /// No description provided for @referralCommissionRate.
  ///
  /// In en, this message translates to:
  /// **'{rate}%'**
  String referralCommissionRate(String rate);

  /// No description provided for @referralManagement.
  ///
  /// In en, this message translates to:
  /// **'Referral Management'**
  String get referralManagement;

  /// No description provided for @referralRules.
  ///
  /// In en, this message translates to:
  /// **'Commission Rules'**
  String get referralRules;

  /// No description provided for @referralApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve & Pay'**
  String get referralApprove;

  /// No description provided for @referralReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get referralReject;

  /// No description provided for @tierTitle.
  ///
  /// In en, this message translates to:
  /// **'Loyalty Program'**
  String get tierTitle;

  /// No description provided for @tierCurrentTier.
  ///
  /// In en, this message translates to:
  /// **'Current Tier'**
  String get tierCurrentTier;

  /// No description provided for @tierPoints.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get tierPoints;

  /// No description provided for @tierPointsValue.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String tierPointsValue(int points);

  /// No description provided for @tierNextTier.
  ///
  /// In en, this message translates to:
  /// **'Next Tier'**
  String get tierNextTier;

  /// No description provided for @tierProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get tierProgress;

  /// No description provided for @tierProgressValue.
  ///
  /// In en, this message translates to:
  /// **'{current} / {needed} pts'**
  String tierProgressValue(int current, int needed);

  /// No description provided for @tierBenefits.
  ///
  /// In en, this message translates to:
  /// **'Benefits'**
  String get tierBenefits;

  /// No description provided for @tierNoBenefits.
  ///
  /// In en, this message translates to:
  /// **'No benefits available'**
  String get tierNoBenefits;

  /// No description provided for @tierBronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get tierBronze;

  /// No description provided for @tierSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get tierSilver;

  /// No description provided for @tierGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get tierGold;

  /// No description provided for @tierPlatinum.
  ///
  /// In en, this message translates to:
  /// **'Platinum'**
  String get tierPlatinum;

  /// No description provided for @tierMultiplier.
  ///
  /// In en, this message translates to:
  /// **'{mult}x points'**
  String tierMultiplier(String mult);

  /// No description provided for @tierPointsToNext.
  ///
  /// In en, this message translates to:
  /// **'{points} pts to next tier'**
  String tierPointsToNext(int points);

  /// No description provided for @tierManagement.
  ///
  /// In en, this message translates to:
  /// **'Tier Management'**
  String get tierManagement;

  /// No description provided for @tierThresholds.
  ///
  /// In en, this message translates to:
  /// **'Tier Thresholds'**
  String get tierThresholds;

  /// No description provided for @tierEditThreshold.
  ///
  /// In en, this message translates to:
  /// **'Edit Threshold'**
  String get tierEditThreshold;

  /// No description provided for @tierEditBenefit.
  ///
  /// In en, this message translates to:
  /// **'Edit Benefit'**
  String get tierEditBenefit;

  /// No description provided for @tierAddBenefit.
  ///
  /// In en, this message translates to:
  /// **'Add Benefit'**
  String get tierAddBenefit;

  /// No description provided for @tierBenefitName.
  ///
  /// In en, this message translates to:
  /// **'Benefit Name'**
  String get tierBenefitName;

  /// No description provided for @tierBenefitDesc.
  ///
  /// In en, this message translates to:
  /// **'Benefit Description'**
  String get tierBenefitDesc;

  /// No description provided for @tierMinPoints.
  ///
  /// In en, this message translates to:
  /// **'Minimum Points'**
  String get tierMinPoints;

  /// No description provided for @tierMaxPoints.
  ///
  /// In en, this message translates to:
  /// **'Maximum Points'**
  String get tierMaxPoints;

  /// No description provided for @tierReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached {tier}!'**
  String tierReached(String tier);

  /// No description provided for @knowledgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get knowledgeTitle;

  /// No description provided for @knowledgeSearch.
  ///
  /// In en, this message translates to:
  /// **'Search articles...'**
  String get knowledgeSearch;

  /// No description provided for @knowledgeCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get knowledgeCategories;

  /// No description provided for @knowledgeAllArticles.
  ///
  /// In en, this message translates to:
  /// **'All Articles'**
  String get knowledgeAllArticles;

  /// No description provided for @knowledgeReadMore.
  ///
  /// In en, this message translates to:
  /// **'Read More'**
  String get knowledgeReadMore;

  /// No description provided for @knowledgeRelated.
  ///
  /// In en, this message translates to:
  /// **'Related Articles'**
  String get knowledgeRelated;

  /// No description provided for @knowledgeNoArticles.
  ///
  /// In en, this message translates to:
  /// **'No articles found'**
  String get knowledgeNoArticles;

  /// No description provided for @knowledgeNoArticlesDesc.
  ///
  /// In en, this message translates to:
  /// **'Articles and guides will appear here'**
  String get knowledgeNoArticlesDesc;

  /// No description provided for @knowledgeViews.
  ///
  /// In en, this message translates to:
  /// **'{count} views'**
  String knowledgeViews(int count);

  /// No description provided for @knowledgeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get knowledgeBookmark;

  /// No description provided for @knowledgeBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get knowledgeBookmarked;

  /// No description provided for @knowledgeRemoveBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove Bookmark'**
  String get knowledgeRemoveBookmark;

  /// No description provided for @knowledgeShareArticle.
  ///
  /// In en, this message translates to:
  /// **'Share Article'**
  String get knowledgeShareArticle;

  /// No description provided for @knowledgeLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get knowledgeLastUpdated;

  /// No description provided for @knowledgeAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get knowledgeAuthor;

  /// No description provided for @knowledgeTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get knowledgeTags;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationTitle;

  /// No description provided for @notificationAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notificationAll;

  /// No description provided for @notificationUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notificationUnread;

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark All Read'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationNoNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationNoNotifications;

  /// No description provided for @notificationNoNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up!'**
  String get notificationNoNotificationsDesc;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @notificationPush.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get notificationPush;

  /// No description provided for @notificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Notifications'**
  String get notificationEmail;

  /// No description provided for @notificationTicketUpdates.
  ///
  /// In en, this message translates to:
  /// **'Ticket Updates'**
  String get notificationTicketUpdates;

  /// No description provided for @notificationNewMessages.
  ///
  /// In en, this message translates to:
  /// **'New Messages'**
  String get notificationNewMessages;

  /// No description provided for @notificationPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get notificationPromotions;

  /// No description provided for @notificationScheduleReminders.
  ///
  /// In en, this message translates to:
  /// **'Schedule Reminders'**
  String get notificationScheduleReminders;

  /// No description provided for @notificationPaymentReminders.
  ///
  /// In en, this message translates to:
  /// **'Payment Reminders'**
  String get notificationPaymentReminders;

  /// No description provided for @notificationJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationJustNow;

  /// No description provided for @notificationSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get notificationSystem;

  /// No description provided for @notificationNoUnread.
  ///
  /// In en, this message translates to:
  /// **'No unread notifications'**
  String get notificationNoUnread;

  /// No description provided for @notificationNoSystem.
  ///
  /// In en, this message translates to:
  /// **'No system messages'**
  String get notificationNoSystem;

  /// No description provided for @notificationSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Announcements will appear here'**
  String get notificationSystemDesc;

  /// No description provided for @notificationDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Notification?'**
  String get notificationDeleteConfirm;

  /// No description provided for @notificationMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get notificationMarkRead;

  /// No description provided for @notificationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications'**
  String get notificationLoadFailed;

  /// No description provided for @notificationPullRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again'**
  String get notificationPullRetry;

  /// No description provided for @notificationDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This notification will be permanently removed.'**
  String get notificationDeleteBody;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Admin Dashboard'**
  String get adminDashboard;

  /// No description provided for @adminAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get adminAnalytics;

  /// No description provided for @adminSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get adminSettings;

  /// No description provided for @adminCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get adminCustomers;

  /// No description provided for @adminEngineers.
  ///
  /// In en, this message translates to:
  /// **'Engineers'**
  String get adminEngineers;

  /// No description provided for @adminMachines.
  ///
  /// In en, this message translates to:
  /// **'Machines'**
  String get adminMachines;

  /// No description provided for @adminTickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get adminTickets;

  /// No description provided for @adminInquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get adminInquiries;

  /// No description provided for @adminBusinessHub.
  ///
  /// In en, this message translates to:
  /// **'Business Hub'**
  String get adminBusinessHub;

  /// No description provided for @adminTotalCustomers.
  ///
  /// In en, this message translates to:
  /// **'Total Customers'**
  String get adminTotalCustomers;

  /// No description provided for @adminTotalEngineers.
  ///
  /// In en, this message translates to:
  /// **'Total Engineers'**
  String get adminTotalEngineers;

  /// No description provided for @adminTotalMachines.
  ///
  /// In en, this message translates to:
  /// **'Total Machines'**
  String get adminTotalMachines;

  /// No description provided for @adminActiveTickets.
  ///
  /// In en, this message translates to:
  /// **'Active Tickets'**
  String get adminActiveTickets;

  /// No description provided for @adminOpenInquiries.
  ///
  /// In en, this message translates to:
  /// **'Open Inquiries'**
  String get adminOpenInquiries;

  /// No description provided for @adminRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get adminRevenue;

  /// No description provided for @adminRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get adminRecentActivity;

  /// No description provided for @adminQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get adminQuickActions;

  /// No description provided for @adminAssignEngineer.
  ///
  /// In en, this message translates to:
  /// **'Assign Engineer'**
  String get adminAssignEngineer;

  /// No description provided for @adminSelectEngineer.
  ///
  /// In en, this message translates to:
  /// **'Select Engineer'**
  String get adminSelectEngineer;

  /// No description provided for @adminNoEngineersAvailable.
  ///
  /// In en, this message translates to:
  /// **'No engineers available'**
  String get adminNoEngineersAvailable;

  /// No description provided for @adminChangeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Status'**
  String get adminChangeStatus;

  /// No description provided for @adminAdminNotes.
  ///
  /// In en, this message translates to:
  /// **'Admin Notes'**
  String get adminAdminNotes;

  /// No description provided for @adminAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get adminAddNote;

  /// No description provided for @adminInternalNotes.
  ///
  /// In en, this message translates to:
  /// **'Internal Notes'**
  String get adminInternalNotes;

  /// No description provided for @adminBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcast Notification'**
  String get adminBroadcast;

  /// No description provided for @adminBroadcastTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get adminBroadcastTitle;

  /// No description provided for @adminBroadcastBody.
  ///
  /// In en, this message translates to:
  /// **'Message Body'**
  String get adminBroadcastBody;

  /// No description provided for @adminBroadcastTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Notification title'**
  String get adminBroadcastTitleHint;

  /// No description provided for @adminBroadcastBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Write your message...'**
  String get adminBroadcastBodyHint;

  /// No description provided for @adminSendBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Send Broadcast'**
  String get adminSendBroadcast;

  /// No description provided for @adminBroadcasting.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get adminBroadcasting;

  /// No description provided for @adminBroadcastSent.
  ///
  /// In en, this message translates to:
  /// **'Broadcast sent successfully'**
  String get adminBroadcastSent;

  /// No description provided for @adminInviteEngineer.
  ///
  /// In en, this message translates to:
  /// **'Invite Engineer'**
  String get adminInviteEngineer;

  /// No description provided for @adminInviteEmail.
  ///
  /// In en, this message translates to:
  /// **'Engineer Email'**
  String get adminInviteEmail;

  /// No description provided for @adminInviteEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter engineer\'s email'**
  String get adminInviteEmailHint;

  /// No description provided for @adminSendInvite.
  ///
  /// In en, this message translates to:
  /// **'Send Invite'**
  String get adminSendInvite;

  /// No description provided for @adminInviteSending.
  ///
  /// In en, this message translates to:
  /// **'Sending invite...'**
  String get adminInviteSending;

  /// No description provided for @adminInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent successfully'**
  String get adminInviteSent;

  /// No description provided for @adminRegisterMachine.
  ///
  /// In en, this message translates to:
  /// **'Register Machine'**
  String get adminRegisterMachine;

  /// No description provided for @adminServiceCalendar.
  ///
  /// In en, this message translates to:
  /// **'Service Calendar'**
  String get adminServiceCalendar;

  /// No description provided for @adminPaymentDashboard.
  ///
  /// In en, this message translates to:
  /// **'Payment Dashboard'**
  String get adminPaymentDashboard;

  /// No description provided for @adminInvoiceManagement.
  ///
  /// In en, this message translates to:
  /// **'Invoice Management'**
  String get adminInvoiceManagement;

  /// No description provided for @adminQuotationManagement.
  ///
  /// In en, this message translates to:
  /// **'Quotation Management'**
  String get adminQuotationManagement;

  /// No description provided for @adminReferralProgram.
  ///
  /// In en, this message translates to:
  /// **'Referral Program'**
  String get adminReferralProgram;

  /// No description provided for @adminLoyaltyTiers.
  ///
  /// In en, this message translates to:
  /// **'Loyalty Tiers'**
  String get adminLoyaltyTiers;

  /// No description provided for @adminManageRules.
  ///
  /// In en, this message translates to:
  /// **'Manage Rules'**
  String get adminManageRules;

  /// No description provided for @adminCustomerDetail.
  ///
  /// In en, this message translates to:
  /// **'Customer Detail'**
  String get adminCustomerDetail;

  /// No description provided for @adminEngineerDetail.
  ///
  /// In en, this message translates to:
  /// **'Engineer Detail'**
  String get adminEngineerDetail;

  /// No description provided for @adminNoCustomers.
  ///
  /// In en, this message translates to:
  /// **'No customers found'**
  String get adminNoCustomers;

  /// No description provided for @adminNoEngineers.
  ///
  /// In en, this message translates to:
  /// **'No engineers found'**
  String get adminNoEngineers;

  /// No description provided for @adminCreateSchedule.
  ///
  /// In en, this message translates to:
  /// **'Create Schedule'**
  String get adminCreateSchedule;

  /// No description provided for @adminViewSchedule.
  ///
  /// In en, this message translates to:
  /// **'View Schedule'**
  String get adminViewSchedule;

  /// No description provided for @adminAllSchedules.
  ///
  /// In en, this message translates to:
  /// **'All Schedules'**
  String get adminAllSchedules;

  /// No description provided for @adminPromotionalBanners.
  ///
  /// In en, this message translates to:
  /// **'Promotional Banners'**
  String get adminPromotionalBanners;

  /// No description provided for @adminMachineManagement.
  ///
  /// In en, this message translates to:
  /// **'Machine Management'**
  String get adminMachineManagement;

  /// No description provided for @adminCustomerManagement.
  ///
  /// In en, this message translates to:
  /// **'Customer Management'**
  String get adminCustomerManagement;

  /// No description provided for @adminEngineerManagement.
  ///
  /// In en, this message translates to:
  /// **'Engineer Management'**
  String get adminEngineerManagement;

  /// No description provided for @adminTicketManagement.
  ///
  /// In en, this message translates to:
  /// **'Ticket Management'**
  String get adminTicketManagement;

  /// No description provided for @adminInquiryManagement.
  ///
  /// In en, this message translates to:
  /// **'Inquiry Management'**
  String get adminInquiryManagement;

  /// No description provided for @adminTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get adminTotalRevenue;

  /// No description provided for @adminMonthlyRevenue.
  ///
  /// In en, this message translates to:
  /// **'Monthly Revenue'**
  String get adminMonthlyRevenue;

  /// No description provided for @adminPendingPayments.
  ///
  /// In en, this message translates to:
  /// **'Pending Payments'**
  String get adminPendingPayments;

  /// No description provided for @adminOverduePayments.
  ///
  /// In en, this message translates to:
  /// **'Overdue Payments'**
  String get adminOverduePayments;

  /// No description provided for @inquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get inquiryTitle;

  /// No description provided for @inquiryDetail.
  ///
  /// In en, this message translates to:
  /// **'Inquiry Detail'**
  String get inquiryDetail;

  /// No description provided for @inquiryCustomerInfo.
  ///
  /// In en, this message translates to:
  /// **'Customer Info'**
  String get inquiryCustomerInfo;

  /// No description provided for @inquiryMachineInfo.
  ///
  /// In en, this message translates to:
  /// **'Machine Info'**
  String get inquiryMachineInfo;

  /// No description provided for @inquiryDealValue.
  ///
  /// In en, this message translates to:
  /// **'Deal Value'**
  String get inquiryDealValue;

  /// No description provided for @inquirySalesPipeline.
  ///
  /// In en, this message translates to:
  /// **'Sales Pipeline'**
  String get inquirySalesPipeline;

  /// No description provided for @inquiryInternalNotes.
  ///
  /// In en, this message translates to:
  /// **'Internal Notes'**
  String get inquiryInternalNotes;

  /// No description provided for @inquiryChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get inquiryChat;

  /// No description provided for @inquiryCreateQuotation.
  ///
  /// In en, this message translates to:
  /// **'Create Quotation'**
  String get inquiryCreateQuotation;

  /// No description provided for @inquiryNoInquiries.
  ///
  /// In en, this message translates to:
  /// **'No inquiries'**
  String get inquiryNoInquiries;

  /// No description provided for @inquiryStageNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get inquiryStageNew;

  /// No description provided for @inquiryStageContacted.
  ///
  /// In en, this message translates to:
  /// **'Contacted'**
  String get inquiryStageContacted;

  /// No description provided for @inquiryStageQualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get inquiryStageQualified;

  /// No description provided for @inquiryStageProposal.
  ///
  /// In en, this message translates to:
  /// **'Proposal'**
  String get inquiryStageProposal;

  /// No description provided for @inquiryStageNegotiation.
  ///
  /// In en, this message translates to:
  /// **'Negotiation'**
  String get inquiryStageNegotiation;

  /// No description provided for @inquiryStageClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed Won'**
  String get inquiryStageClosed;

  /// No description provided for @inquiryStageLost.
  ///
  /// In en, this message translates to:
  /// **'Closed Lost'**
  String get inquiryStageLost;

  /// No description provided for @engineerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Engineer Dashboard'**
  String get engineerDashboard;

  /// No description provided for @engineerMyAssignments.
  ///
  /// In en, this message translates to:
  /// **'My Assignments'**
  String get engineerMyAssignments;

  /// No description provided for @engineerToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get engineerToday;

  /// No description provided for @engineerUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get engineerUpcoming;

  /// No description provided for @engineerDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get engineerDone;

  /// No description provided for @engineerNoAssignments.
  ///
  /// In en, this message translates to:
  /// **'No assignments'**
  String get engineerNoAssignments;

  /// No description provided for @engineerNoToday.
  ///
  /// In en, this message translates to:
  /// **'No tasks for today'**
  String get engineerNoToday;

  /// No description provided for @engineerNoTodayDesc.
  ///
  /// In en, this message translates to:
  /// **'Enjoy your free time!'**
  String get engineerNoTodayDesc;

  /// No description provided for @engineerNoUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No upcoming tasks'**
  String get engineerNoUpcoming;

  /// No description provided for @engineerNoUpcomingDesc.
  ///
  /// In en, this message translates to:
  /// **'No scheduled tasks ahead'**
  String get engineerNoUpcomingDesc;

  /// No description provided for @engineerNoDone.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks'**
  String get engineerNoDone;

  /// No description provided for @engineerNoDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks will appear here'**
  String get engineerNoDoneDesc;

  /// No description provided for @engineerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get engineerConfirm;

  /// No description provided for @engineerStart.
  ///
  /// In en, this message translates to:
  /// **'Start Service'**
  String get engineerStart;

  /// No description provided for @engineerComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get engineerComplete;

  /// No description provided for @engineerServiceReport.
  ///
  /// In en, this message translates to:
  /// **'Service Report'**
  String get engineerServiceReport;

  /// No description provided for @engineerReportRequired.
  ///
  /// In en, this message translates to:
  /// **'A service report is required to complete this service'**
  String get engineerReportRequired;

  /// No description provided for @engineerWriteReport.
  ///
  /// In en, this message translates to:
  /// **'Write Report'**
  String get engineerWriteReport;

  /// No description provided for @engineerReportHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the work performed, parts used, findings...'**
  String get engineerReportHint;

  /// No description provided for @engineerSubmitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get engineerSubmitReport;

  /// No description provided for @engineerReportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted'**
  String get engineerReportSubmitted;

  /// No description provided for @engineerNotes.
  ///
  /// In en, this message translates to:
  /// **'Engineer Notes'**
  String get engineerNotes;

  /// No description provided for @engineerUpdateNotes.
  ///
  /// In en, this message translates to:
  /// **'Update Notes'**
  String get engineerUpdateNotes;

  /// No description provided for @engineerNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Your notes about this service...'**
  String get engineerNotesHint;

  /// No description provided for @engineerNotesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Notes updated'**
  String get engineerNotesUpdated;

  /// No description provided for @engineerCustomerRating.
  ///
  /// In en, this message translates to:
  /// **'Customer Rating'**
  String get engineerCustomerRating;

  /// No description provided for @engineerNoRating.
  ///
  /// In en, this message translates to:
  /// **'No rating yet'**
  String get engineerNoRating;

  /// No description provided for @engineerPendingTasks.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get engineerPendingTasks;

  /// No description provided for @engineerActiveTasks.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get engineerActiveTasks;

  /// No description provided for @engineerCompletedTasks.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get engineerCompletedTasks;

  /// No description provided for @engineerSchedule.
  ///
  /// In en, this message translates to:
  /// **'My Schedule'**
  String get engineerSchedule;

  /// No description provided for @engineerGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String engineerGreeting(String name);

  /// No description provided for @engineerTodaySummary.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Summary'**
  String get engineerTodaySummary;

  /// No description provided for @engineerPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String engineerPendingCount(int count);

  /// No description provided for @engineerActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String engineerActiveCount(int count);

  /// No description provided for @engineerCallCustomer.
  ///
  /// In en, this message translates to:
  /// **'Call Customer'**
  String get engineerCallCustomer;

  /// No description provided for @engineerViewLocation.
  ///
  /// In en, this message translates to:
  /// **'View Location'**
  String get engineerViewLocation;

  /// No description provided for @engineerStarted.
  ///
  /// In en, this message translates to:
  /// **'Service started'**
  String get engineerStarted;

  /// No description provided for @engineerCompleted.
  ///
  /// In en, this message translates to:
  /// **'Service completed'**
  String get engineerCompleted;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get statusInactive;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// No description provided for @statusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpen;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @statusEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get statusEscalated;

  /// No description provided for @statusOnHold.
  ///
  /// In en, this message translates to:
  /// **'On Hold'**
  String get statusOnHold;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get statusSent;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get statusUnpaid;

  /// No description provided for @statusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get statusOverdue;

  /// No description provided for @statusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get statusPartial;

  /// No description provided for @statusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get statusScheduled;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusRescheduled.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled'**
  String get statusRescheduled;

  /// No description provided for @statusRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get statusRequested;

  /// No description provided for @timeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timeToday;

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timeYesterday;

  /// No description provided for @timeTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get timeTomorrow;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeDaysAgo(int count);

  /// No description provided for @timeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String timeMinutes(int count);

  /// No description provided for @timeHours.
  ///
  /// In en, this message translates to:
  /// **'{count} hours'**
  String timeHours(int count);

  /// No description provided for @timeDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String timeDays(int count);

  /// No description provided for @timeWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count} weeks'**
  String timeWeeks(int count);

  /// No description provided for @timeMonths.
  ///
  /// In en, this message translates to:
  /// **'{count} months'**
  String timeMonths(int count);

  /// No description provided for @timeAgo.
  ///
  /// In en, this message translates to:
  /// **'{time} ago'**
  String timeAgo(String time);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again.'**
  String get errorTimeout;

  /// No description provided for @errorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again.'**
  String get errorUnauthorized;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorNotFound;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'Server error. Please try again later.'**
  String get errorServer;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid input. Please check and try again.'**
  String get errorInvalidInput;

  /// No description provided for @errorRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get errorRequired;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get errorInvalidEmail;

  /// No description provided for @errorPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get errorPasswordShort;

  /// No description provided for @errorNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get errorNoInternet;

  /// No description provided for @errorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data'**
  String get errorLoadFailed;

  /// No description provided for @errorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save'**
  String get errorSaveFailed;

  /// No description provided for @errorDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete'**
  String get errorDeleteFailed;

  /// No description provided for @errorUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload'**
  String get errorUploadFailed;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errorPermissionDenied;

  /// No description provided for @errorAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Already exists'**
  String get errorAlreadyExists;

  /// No description provided for @errorMinLength.
  ///
  /// In en, this message translates to:
  /// **'Must be at least {count} characters'**
  String errorMinLength(int count);

  /// No description provided for @errorMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Must be at most {count} characters'**
  String errorMaxLength(int count);

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get validationRequired;

  /// No description provided for @validationEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get validationEmail;

  /// No description provided for @validationPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get validationPhone;

  /// No description provided for @validationMinLength.
  ///
  /// In en, this message translates to:
  /// **'Minimum {count} characters required'**
  String validationMinLength(int count);

  /// No description provided for @validationPasswordMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get validationPasswordMatch;

  /// No description provided for @validationNumberOnly.
  ///
  /// In en, this message translates to:
  /// **'Please enter numbers only'**
  String get validationNumberOnly;

  /// No description provided for @validationPositiveNumber.
  ///
  /// In en, this message translates to:
  /// **'Must be a positive number'**
  String get validationPositiveNumber;

  /// No description provided for @validationSelectOption.
  ///
  /// In en, this message translates to:
  /// **'Please select an option'**
  String get validationSelectOption;

  /// No description provided for @validationDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please select a valid date'**
  String get validationDateInvalid;

  /// No description provided for @validationAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get validationAmountInvalid;

  /// No description provided for @orderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Machine'**
  String get orderTitle;

  /// No description provided for @orderFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Machine Order Form'**
  String get orderFormTitle;

  /// No description provided for @orderQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get orderQuantity;

  /// No description provided for @orderDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address'**
  String get orderDeliveryAddress;

  /// No description provided for @orderDeliveryHint.
  ///
  /// In en, this message translates to:
  /// **'Enter delivery address'**
  String get orderDeliveryHint;

  /// No description provided for @orderAdditionalNotes.
  ///
  /// In en, this message translates to:
  /// **'Additional Notes'**
  String get orderAdditionalNotes;

  /// No description provided for @orderNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Any special requirements...'**
  String get orderNotesHint;

  /// No description provided for @orderSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Order'**
  String get orderSubmit;

  /// No description provided for @orderSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting order...'**
  String get orderSubmitting;

  /// No description provided for @orderSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Order submitted successfully'**
  String get orderSubmitted;

  /// No description provided for @orderReview.
  ///
  /// In en, this message translates to:
  /// **'Review Order'**
  String get orderReview;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get orderSummary;

  /// No description provided for @orderMachine.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get orderMachine;

  /// No description provided for @orderUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get orderUnitPrice;

  /// No description provided for @orderTotalPrice.
  ///
  /// In en, this message translates to:
  /// **'Total Price'**
  String get orderTotalPrice;

  /// No description provided for @salesStageNew.
  ///
  /// In en, this message translates to:
  /// **'New Lead'**
  String get salesStageNew;

  /// No description provided for @salesStageContacted.
  ///
  /// In en, this message translates to:
  /// **'Contacted'**
  String get salesStageContacted;

  /// No description provided for @salesStageQualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get salesStageQualified;

  /// No description provided for @salesStageProposal.
  ///
  /// In en, this message translates to:
  /// **'Proposal Sent'**
  String get salesStageProposal;

  /// No description provided for @salesStageNegotiation.
  ///
  /// In en, this message translates to:
  /// **'Negotiation'**
  String get salesStageNegotiation;

  /// No description provided for @salesStageClosedWon.
  ///
  /// In en, this message translates to:
  /// **'Closed Won'**
  String get salesStageClosedWon;

  /// No description provided for @salesStageClosedLost.
  ///
  /// In en, this message translates to:
  /// **'Closed Lost'**
  String get salesStageClosedLost;

  /// No description provided for @salesStageFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Follow Up'**
  String get salesStageFollowUp;

  /// No description provided for @pointsEarned.
  ///
  /// In en, this message translates to:
  /// **'+{points} points earned!'**
  String pointsEarned(int points);

  /// No description provided for @pointsAccountCreation.
  ///
  /// In en, this message translates to:
  /// **'Welcome bonus'**
  String get pointsAccountCreation;

  /// No description provided for @pointsProfileComplete.
  ///
  /// In en, this message translates to:
  /// **'Profile completion bonus'**
  String get pointsProfileComplete;

  /// No description provided for @pointsTicketCreated.
  ///
  /// In en, this message translates to:
  /// **'Ticket creation reward'**
  String get pointsTicketCreated;

  /// No description provided for @pointsArticleRead.
  ///
  /// In en, this message translates to:
  /// **'Knowledge article reward'**
  String get pointsArticleRead;

  /// No description provided for @pointsServiceRating.
  ///
  /// In en, this message translates to:
  /// **'Service rating reward'**
  String get pointsServiceRating;

  /// No description provided for @pointsMachinePurchase.
  ///
  /// In en, this message translates to:
  /// **'Machine purchase reward'**
  String get pointsMachinePurchase;

  /// No description provided for @pointsInstallmentPaid.
  ///
  /// In en, this message translates to:
  /// **'Payment reward'**
  String get pointsInstallmentPaid;

  /// No description provided for @pointsTicketResolved.
  ///
  /// In en, this message translates to:
  /// **'Ticket resolved reward'**
  String get pointsTicketResolved;

  /// No description provided for @pointsDailyLogin.
  ///
  /// In en, this message translates to:
  /// **'Daily login reward'**
  String get pointsDailyLogin;

  /// No description provided for @pointsReferralSignup.
  ///
  /// In en, this message translates to:
  /// **'Referral signup reward'**
  String get pointsReferralSignup;

  /// No description provided for @pointsReferralQualified.
  ///
  /// In en, this message translates to:
  /// **'Referral qualified reward'**
  String get pointsReferralQualified;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this? This action cannot be undone.'**
  String get deleteConfirmMessage;

  /// No description provided for @cancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelConfirmTitle;

  /// No description provided for @cancelConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel?'**
  String get cancelConfirmMessage;

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Discard them?'**
  String get unsavedChangesMessage;

  /// No description provided for @discardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// No description provided for @keepEditingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep Editing'**
  String get keepEditingButton;

  /// No description provided for @emptyStateTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets found'**
  String get emptyStateTickets;

  /// No description provided for @emptyStateTicketsDesc.
  ///
  /// In en, this message translates to:
  /// **'Create a support ticket to get help'**
  String get emptyStateTicketsDesc;

  /// No description provided for @emptyStateMachines.
  ///
  /// In en, this message translates to:
  /// **'No machines registered'**
  String get emptyStateMachines;

  /// No description provided for @emptyStateMachinesDesc.
  ///
  /// In en, this message translates to:
  /// **'Register your machines for service tracking'**
  String get emptyStateMachinesDesc;

  /// No description provided for @emptyStateSchedules.
  ///
  /// In en, this message translates to:
  /// **'No schedules found'**
  String get emptyStateSchedules;

  /// No description provided for @emptyStateSchedulesDesc.
  ///
  /// In en, this message translates to:
  /// **'Service schedules will appear here'**
  String get emptyStateSchedulesDesc;

  /// No description provided for @emptyStateInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices found'**
  String get emptyStateInvoices;

  /// No description provided for @emptyStateInvoicesDesc.
  ///
  /// In en, this message translates to:
  /// **'Your invoices will appear here'**
  String get emptyStateInvoicesDesc;

  /// No description provided for @emptyStateQuotations.
  ///
  /// In en, this message translates to:
  /// **'No quotations found'**
  String get emptyStateQuotations;

  /// No description provided for @emptyStateQuotationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Your quotations will appear here'**
  String get emptyStateQuotationsDesc;

  /// No description provided for @emptyStateNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get emptyStateNotifications;

  /// No description provided for @emptyStateNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up!'**
  String get emptyStateNotificationsDesc;

  /// No description provided for @emptyStateCustomers.
  ///
  /// In en, this message translates to:
  /// **'No customers found'**
  String get emptyStateCustomers;

  /// No description provided for @emptyStateEngineers.
  ///
  /// In en, this message translates to:
  /// **'No engineers found'**
  String get emptyStateEngineers;

  /// No description provided for @emptyStateReferrals.
  ///
  /// In en, this message translates to:
  /// **'No referrals yet'**
  String get emptyStateReferrals;

  /// No description provided for @emptyStateReferralsDesc.
  ///
  /// In en, this message translates to:
  /// **'Share your referral code to get started'**
  String get emptyStateReferralsDesc;

  /// No description provided for @emptyStateArticles.
  ///
  /// In en, this message translates to:
  /// **'No articles found'**
  String get emptyStateArticles;

  /// No description provided for @emptyStateArticlesDesc.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base articles will appear here'**
  String get emptyStateArticlesDesc;

  /// No description provided for @emptyStatePayments.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded'**
  String get emptyStatePayments;

  /// No description provided for @emptyStatePaymentsDesc.
  ///
  /// In en, this message translates to:
  /// **'Payment records will appear here'**
  String get emptyStatePaymentsDesc;

  /// No description provided for @calendarMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarMonth;

  /// No description provided for @calendarWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarWeek;

  /// No description provided for @calendarDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get calendarDay;

  /// No description provided for @calendarToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calendarToday;

  /// No description provided for @calendarNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No events on this day'**
  String get calendarNoEvents;

  /// No description provided for @calendarEventsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} events'**
  String calendarEventsCount(int count);

  /// No description provided for @analyticsOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get analyticsOverview;

  /// No description provided for @analyticsTicketsByStatus.
  ///
  /// In en, this message translates to:
  /// **'Tickets by Status'**
  String get analyticsTicketsByStatus;

  /// No description provided for @analyticsTicketsByPriority.
  ///
  /// In en, this message translates to:
  /// **'Tickets by Priority'**
  String get analyticsTicketsByPriority;

  /// No description provided for @analyticsResponseTime.
  ///
  /// In en, this message translates to:
  /// **'Avg. Response Time'**
  String get analyticsResponseTime;

  /// No description provided for @analyticsResolutionTime.
  ///
  /// In en, this message translates to:
  /// **'Avg. Resolution Time'**
  String get analyticsResolutionTime;

  /// No description provided for @analyticsCustomerGrowth.
  ///
  /// In en, this message translates to:
  /// **'Customer Growth'**
  String get analyticsCustomerGrowth;

  /// No description provided for @analyticsRevenueChart.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get analyticsRevenueChart;

  /// No description provided for @analyticsTopEngineers.
  ///
  /// In en, this message translates to:
  /// **'Top Engineers'**
  String get analyticsTopEngineers;

  /// No description provided for @analyticsCustomerSatisfaction.
  ///
  /// In en, this message translates to:
  /// **'Customer Satisfaction'**
  String get analyticsCustomerSatisfaction;

  /// No description provided for @analyticsPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get analyticsPeriodWeek;

  /// No description provided for @analyticsPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get analyticsPeriodMonth;

  /// No description provided for @analyticsPeriodQuarter.
  ///
  /// In en, this message translates to:
  /// **'This Quarter'**
  String get analyticsPeriodQuarter;

  /// No description provided for @analyticsPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get analyticsPeriodYear;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get settingsDarkMode;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get settingsHelp;

  /// No description provided for @settingsRateApp.
  ///
  /// In en, this message translates to:
  /// **'Rate App'**
  String get settingsRateApp;

  /// No description provided for @settingsShareApp.
  ///
  /// In en, this message translates to:
  /// **'Share App'**
  String get settingsShareApp;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTerms;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get settingsAppVersion;

  /// No description provided for @settingsSelectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get settingsSelectLanguage;

  /// No description provided for @settingsLanguageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language changed'**
  String get settingsLanguageChanged;

  /// No description provided for @settingsThemeChanged.
  ///
  /// In en, this message translates to:
  /// **'Theme changed'**
  String get settingsThemeChanged;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'si', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'si':
      return SSi();
    case 'ta':
      return STa();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
