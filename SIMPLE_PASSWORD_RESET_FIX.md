# Password Reset Page - Language Switcher Fix

The AnimatedBuilder addition caused syntax errors. Here's the correct structure:

## Fix the build() method

**Find this section** (around line 222):

```dart
@override
Widget build(BuildContext context) {
  return WillPopScope(
    onWillPop: () async {
      // ... existing code
    },
    child: AnimatedBuilder(
      animation: _lc,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_t('reset_password')),
          actions: [
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: _t('switch_language'),
              onPressed: () async {
                await _lc.toggleLanguage();
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              // ... all the content
            ),
          ),
        ),
      ),
    ),
  );
}
```

**The closing should be:**
```dart
              ],  // End of Column children
            ),    // End of Column
          ),      // End of SingleChildScrollView
        ),        // End of SafeArea (body)
      ),          // End of Scaffold
    ),            // End of AnimatedBuilder child
  );              // End of WillPopScope
}                 // End of build method
```

---

## Translations Already Added

✅ **l10n.dart updated** with:
- `email_verified_banner` for all 3 languages
- All password reset strings translated
- Step indicators will use translated labels

---

## Profile Page email_verified_banner

The profile page already uses `_t('email_verified_banner')` correctly (line 647).

The translation is now in l10n.dart:
- English: "Email verified"
- Amharic: "ኢሜል ተረጋግጧል"
- Oromo: "Imeeliin mirkanaaʼe"

---

## Summary

**Issue:** Widget nesting syntax errors from AnimatedBuilder  
**Solution:** Manually verify the closing parentheses match the structure above

**Translations:** All complete and working  
**Language switcher:** Icon added to app bar  
**Profile page:** Already using translations correctly
