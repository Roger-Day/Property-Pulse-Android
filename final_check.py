import re
import os

files = [
    "lib/models/review_model.dart",
    "lib/models/notification_model.dart",
    "lib/repositories/user_profile_repository.dart",
    "lib/screens/notifications/notifications_screen.dart",
    "lib/screens/reviews/reviews_screen.dart",
    "lib/screens/explore/property_detail_screen.dart",
    "lib/router/app_router.dart",
    "lib/screens/home/home_screen.dart",
]

issues = {}

for filepath in files:
    if not os.path.exists(filepath):
        issues[filepath] = [f"FILE NOT FOUND"]
        continue
    
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
        lines = content.split('\n')
    
    file_issues = []
    
    # Check for curly quotes (U+2018, U+2019)
    if '\u2018' in content or '\u2019' in content:
        for i, line in enumerate(lines, 1):
            if '\u2018' in line or '\u2019' in line:
                file_issues.append(f"Line {i}: Contains curly quotes (U+2018/U+2019)")
    
    # Check for undefined context.read<>() calls in screens
    if 'screens' in filepath and 'context.read' in content:
        pattern = r'context\.read<(\w+)>'
        for i, line in enumerate(lines, 1):
            matches = re.findall(pattern, line)
            for match in matches:
                # Known providers that should be defined elsewhere
                allowed = ['AuthProvider', 'UserProfileRepository', 'PropertyRepository', 
                          'SavedProvider', 'ProjectRepository']
                if match not in allowed:
                    file_issues.append(f"Line {i}: Potentially undefined context.read<{match}>")
    
    # Check for incomplete switch statements (missing default: or =>)
    if '.dart' in filepath:
        switch_pattern = r'switch\s*\([^)]+\)\s*\{'
        for i, line in enumerate(lines, 1):
            if re.search(switch_pattern, line):
                # Look ahead for completeness
                j = i
                depth = 0
                has_default = False
                while j < len(lines) and j < i + 30:
                    if 'default:' in lines[j-1] or '_' in lines[j-1]:
                        has_default = True
                    if '}' in lines[j-1]:
                        break
                    j += 1
                # Don't flag as issue, just noting
    
    if file_issues:
        issues[filepath] = file_issues
    else:
        issues[filepath] = ["OK"]

for f in sorted(issues.keys()):
    status = "OK" if issues[f] == ["OK"] else "ISSUES"
    print(f"{f:60} {status:10}")
    for issue in issues[f]:
        if issue != "OK":
            print(f"  - {issue}")

print(f"\nTotal files checked: {len(files)}")
print(f"Files with issues: {len([f for f in issues if issues[f] != ['OK']])}")
