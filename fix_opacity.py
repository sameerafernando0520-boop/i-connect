#!/usr/bin/env python3
"""
Batch replace .withOpacity() with .withAlpha() equivalents
Converts opacity percentages (0.0-1.0) to alpha (0-255)
"""

import re
import os
from pathlib import Path

# Mapping of opacity values to alpha values
OPACITY_TO_ALPHA = {
    '0.01': '3',
    '0.015': '4',
    '0.025': '6',
    '0.03': '8',
    '0.04': '10',
    '0.05': '13',
    '0.06': '15',
    '0.07': '18',
    '0.08': '20',
    '0.1': '26',
    '0.12': '31',
    '0.15': '38',
    '0.18': '46',
    '0.2': '51',
    '0.25': '64',
    '0.3': '77',
    '0.35': '89',
    '0.4': '102',
    '0.45': '115',
    '0.5': '128',
    '0.55': '140',
    '0.6': '153',
    '0.7': '179',
    '0.8': '204',
    '0.9': '230',
}

def convert_opacity_to_alpha(content):
    """Convert all .withOpacity(X) calls to .withAlpha(Y)"""
    result = content
    
    # Handle dynamic opacity values (isDark ? 0.X : 0.Y)
    # Pattern: .withOpacity(isDark ? 0.XX : 0.YY)
    def replace_dynamic(match):
        opacity1 = match.group(1)
        opacity2 = match.group(2)
        alpha1 = OPACITY_TO_ALPHA.get(opacity1, None)
        alpha2 = OPACITY_TO_ALPHA.get(opacity2, None)
        if alpha1 and alpha2:
            return f".withAlpha(isDark ? {alpha1} : {alpha2})"
        return match.group(0)
    
    result = re.sub(
        r'\.withOpacity\(isDark \? (0\.\d+) : (0\.\d+)\)',
        replace_dynamic,
        result
    )
    
    # Handle fixed opacity values
    # Pattern: .withOpacity(0.XX)
    def replace_fixed(match):
        opacity = match.group(1)
        alpha = OPACITY_TO_ALPHA.get(opacity, None)
        if alpha:
            return f".withAlpha({alpha})"
        return match.group(0)
    
    result = re.sub(
        r'\.withOpacity\((0\.\d+)\)',
        replace_fixed,
        result
    )
    
    return result

def process_dart_files(directory):
    """Process all dart files in the screens directory"""
    screens_dir = Path(directory) / 'lib' / 'screens'
    dart_files = list(screens_dir.glob('**/*.dart'))
    
    total_files = len(dart_files)
    replacements_count = 0
    
    for file_path in dart_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                original_content = f.read()
            
            new_content = convert_opacity_to_alpha(original_content)
            
            if original_content != new_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                
                # Count replacements
                replacements = len(re.findall(r'\.withAlpha\(', new_content)) - len(
                    re.findall(r'\.withAlpha\(', original_content)
                )
                replacements_count += replacements
                print(f"✓ {file_path.relative_to(directory)}: {replacements} replacements")
        
        except Exception as e:
            print(f"✗ Error processing {file_path}: {e}")
    
    print(f"\n✓ Processed {total_files} files")
    print(f"✓ Total replacements: {replacements_count}")

if __name__ == '__main__':
    import sys
    directory = sys.argv[1] if len(sys.argv) > 1 else '.'
    process_dart_files(directory)
    print("\n✓ Batch conversion complete!")
