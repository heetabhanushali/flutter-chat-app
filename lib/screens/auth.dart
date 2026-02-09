import 'package:chat_app/widgets/navigation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() {
    return _AuthScreenState();
  }
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();
  var is_login = true;
  var obscure_text = true;
  var obscure_confirm_text = true; // Added for confirm password field
  var email = '';
  var password = '';
  var confirm_password = ''; // Added confirm password variable
  var username = '';
  final _form = GlobalKey<FormState>();

  // Username validation function
  bool _isValidUsername(String username) {
    // Regular expression to match only a-z, A-Z, 0-9, _, .
    final RegExp usernameRegex = RegExp(r'^[a-zA-Z0-9_.]+$');
    return usernameRegex.hasMatch(username);
  }

  void _showForgotPasswordDialog() {
    String resetEmail = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reset Password'),
          content: SizedBox(
            width: 300,
            height: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter your email address below to receive a password reset link.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    resetEmail = value.trim();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (resetEmail.isEmpty || !resetEmail.contains('@')) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid email')),
                    );
                  }
                  return;
                }

                Navigator.of(ctx).pop();

                try {
                  await _authService.resetPassword(resetEmail);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password reset email sent! Check your inbox.'),
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $error')),
                    );
                  }
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  void _submit() async {
    final isValid = _form.currentState!.validate();
    if (!isValid) {
      return;
    }
    _form.currentState!.save();

    try {
      if (is_login) {
        // LOGIN: email or username allowed

        String emailToLogin = email.trim();

        // If input looks like a username (no '@'), look up email by username
        if (!emailToLogin.contains('@')) {
          try {
            final foundEmail = await _authService.getEmailByUsername(emailToLogin);
            if (foundEmail == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Username "$emailToLogin" not found. Please check your username or use email instead.')),
                );
              }
              return;
            }
            emailToLogin = foundEmail;
          } catch (e) {
            print('Error looking up username: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error looking up username. Please try using your email instead.')),
              );
            }
            return;
          }
        }

        final response = await _authService.signIn(
          email: emailToLogin,
          password: password,
        );

        if (response.session == null) {
          throw AuthException('Login failed');
        }

        await _authService.recoverEncryptionKeys(
          userId: response.session!.user.id,
          password: password,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login successful!')),
          );
          
          // Navigate to home screen after successful login
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => Navigation()));
        }
      } else {
        // REGISTRATION
        final taken = await _authService.isUsernameTaken(username);
        if (taken) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Username already exists. Please choose another one.')),
            );
          }
          return;
        }

        final response = await _authService.signUp(
          email: email.trim(),
          password: password,
          username: username,
        );
        try {
          await _authService.createUserProfile(
            userId: response.user!.id,
            username: username,
            email: email.trim(),
          );

          await _authService.setupEncryptionKeys(
            userId: response.user!.id,
            password: password,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Registration successful!')),
            );

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => Navigation()),
            );
          }
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Username already exists. Please choose another one.')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Database error: ${e.message}')),
              );
            }
          }
          return;
        }
      }
    } on AuthException catch (error) {
      print('Auth error: ${error.message}'); // Debug log
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      print('General error: $error'); // Debug log
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/auth_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 250, left: 20, right: 20, bottom: 10),
          child: Center(
            child: SingleChildScrollView(
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    Text(is_login ? 'Login' : 'Register', 
                         style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 50),

                    // USERNAME FIELD (only for registration)
                    if (!is_login) ...[
                      TextFormField(
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary
                        ),
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a username';
                          }
                          if (value.trim().length < 3) {
                            return 'Username must be at least 3 characters long';
                          }
                          if (!_isValidUsername(value.trim())) {
                            return 'Username can only contain letters, numbers, dots (.), and underscores (_)';
                          }
                          return null;
                        },
                        onSaved: (value) {
                          username = value!.trim();
                        },
                        decoration: InputDecoration(
                          hintText: 'Username',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 17
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.onPrimary.withAlpha(150),
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              width: 2,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          )
                        ),
                      ),
                      const SizedBox(height: 25),
                    ],

                    // EMAIL FIELD
                    TextFormField(
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      validator: (value) {
                        if(!is_login){
                          if (value == null || value.trim().isEmpty || !value.contains('@')) {
                            return 'Please enter valid email address';
                          }
                        }
                        return null;
                      },
                      onSaved: (value) {
                        email = value!;
                      },
                      decoration: InputDecoration(
                        hintText: is_login? 'Email / Username' : 'Email',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 17
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.onPrimary.withAlpha(150),
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            width: 2,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        )
                      ),
                    ),
                    const SizedBox(height: 25),

                    // PASSWORD FIELD
                    TextFormField(
                      obscureText: obscure_text,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty || value.length < 6) {
                          return 'Password must be at least 6 characters long';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        password = value!;
                      },
                      onChanged: (value) {
                        password = value; // Update password as user types for real-time validation
                      },
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary
                      ),
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 17
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.onPrimary.withAlpha(150),
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            width: 2,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              obscure_text = !obscure_text;
                            });
                          }, 
                          icon: obscure_text ? 
                            Icon(Icons.visibility_off_outlined, color: Theme.of(context).colorScheme.onPrimary) :
                            Icon(Icons.visibility_outlined, color: Theme.of(context).colorScheme.onPrimary)
                        )
                      ),
                    ),
                    
                    // CONFIRM PASSWORD FIELD (only for registration)
                    if (!is_login) ...[
                      const SizedBox(height: 25),
                      TextFormField(
                        obscureText: obscure_confirm_text,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != password) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        onSaved: (value) {
                          confirm_password = value!;
                        },
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary
                        ),
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: 'Confirm Password',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 17
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.onPrimary.withAlpha(150),
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              width: 2,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                obscure_confirm_text = !obscure_confirm_text;
                              });
                            }, 
                            icon: obscure_confirm_text ? 
                              Icon(Icons.visibility_off_outlined, color: Theme.of(context).colorScheme.onPrimary) :
                              Icon(Icons.visibility_outlined, color: Theme.of(context).colorScheme.onPrimary)
                          )
                        ),
                      ),
                    ],
                    
                    if (is_login) const SizedBox(height: 10),

                    // FORGOT PASSWORD
                    if (is_login) GestureDetector(
                      onTap: () {
                        _showForgotPasswordDialog();
                      },
                      child: Text('Forgot Password?',
                        style: Theme.of(context).textTheme.bodySmall
                      ),
                    ),
                    const SizedBox(height: 40),

                    // LOGIN/REGISTER BUTTON
                    FilledButton(
                      onPressed: _submit,
                      style: TextButton.styleFrom(
                        minimumSize: Size.fromHeight(60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        backgroundColor: Theme.of(context).colorScheme.onPrimary,
                      ), 
                      child: Text(is_login ? 'Login' : 'Register', 
                                 style: Theme.of(context).textTheme.bodyMedium),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(is_login ? 'Don\'t have an account yet?' : 'Already have an account?', 
                             style: Theme.of(context).textTheme.bodySmall),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              is_login = !is_login;
                              _form.currentState?.reset();
                            });
                          }, 
                          child: Text(is_login ? 'Register Here' : 'Login', 
                                     style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                       decoration: TextDecoration.underline,
                                     ))
                        )
                      ],
                    )
                  ],
                ),
              )
            ),
          ),
        ),
      ),
    );
  }
}