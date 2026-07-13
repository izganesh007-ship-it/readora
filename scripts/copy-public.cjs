const fs = require('fs');
const path = require('path');

const root = process.cwd();
const from = path.join(root, 'public');
const to = path.join(root, 'dist', 'public');

function copyDir(src, dest) {
  if (!fs.existsSync(src)) {
    console.log('No public directory found, skipping copy.');
    return;
  }

  fs.mkdirSync(dest, { recursive: true });

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

copyDir(from, to);
console.log(`Copied ${from} -> ${to}`);
