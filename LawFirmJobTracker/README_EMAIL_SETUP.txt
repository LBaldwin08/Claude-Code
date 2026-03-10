HOW TO SET UP GMAIL FOR THE JOB TRACKER NEWSLETTER
====================================================

Gmail requires an "App Password" for scripts — your regular Gmail password
will NOT work. Follow these steps once:

STEP 1: Enable 2-Step Verification (required)
----------------------------------------------
1. Go to: https://myaccount.google.com/security
2. Under "How you sign in to Google", click "2-Step Verification"
3. Follow the prompts to turn it on (if not already enabled)

STEP 2: Create an App Password
----------------------------------------------
1. Go to: https://myaccount.google.com/apppasswords
   (or: Google Account → Security → 2-Step Verification → scroll to bottom → App passwords)
2. In the "App name" field, type:  Law Firm Job Tracker
3. Click "Create"
4. Google will show a 16-character password like:  abcd efgh ijkl mnop
5. Copy it immediately (it is only shown once)

STEP 3: Edit config.ps1
----------------------------------------------
1. Open:  C:\Users\lbald\Desktop\LawFirmJobTracker\config.ps1
2. Replace "your.email@gmail.com"   with your actual Gmail address
3. Replace "xxxx xxxx xxxx xxxx"    with the App Password from Step 2
4. Save the file

Example config.ps1:
   $GMAIL_ADDRESS      = "lbaldwin08@gmail.com"
   $GMAIL_APP_PASSWORD = "abcd efgh ijkl mnop"

SMTP SETTINGS (for reference — already built into the script)
----------------------------------------------
   Server:     smtp.gmail.com
   Port:       587
   Encryption: TLS (STARTTLS)

TROUBLESHOOTING
----------------------------------------------
- "Authentication failed"     → Double-check the App Password; retype it carefully
- "Less secure app" error     → You need an App Password, not your regular password
- Email lands in Spam         → Mark it "Not spam" once; Gmail will learn
- No email received           → Check the script log output for error details
