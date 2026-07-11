import re

files = {
    "lib/models/review_model.dart": "enum switch statements",
    "lib/screens/notifications/notifications_screen.dart": "notification handling",
    "lib/screens/explore/property_detail_screen.dart": "navigation and message handling",
}

for filepath, desc in files.items():
    print(f"\n{'='*70}")
    print(f"{filepath} ({desc})")
    print('='*70)
    
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    
    in_switch = False
    switch_start = 0
    for i, line in enumerate(lines, 1):
        if 'switch' in line and '{' in line:
            in_switch = True
            switch_start = i
            print(f"\nSwitch statement at line {i}:")
            # Print context
            for j in range(max(0, i-2), min(len(lines), i+20)):
                marker = ">>>" if j == i-1 else "   "
                print(f"{marker} {j+1:4d}: {lines[j].rstrip()}")
