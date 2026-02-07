#!/usr/bin/env node
// generate-icons.js - Générateur automatique d'icônes PWA

const fs = require('fs');
const path = require('path');

console.log(`
╔════════════════════════════════════════════════╗
║   🎨 Générateur d'Icônes PWA pour NBFO        ║
╚════════════════════════════════════════════════╝
`);

// Instructions
console.log('📋 Instructions :');
console.log('1. Préparez une image 512×512px (logo NBFO)');
console.log('2. Utilisez un outil en ligne :');
console.log('   → https://www.pwabuilder.com/imageGenerator');
console.log('   → https://realfavicongenerator.net/');
console.log('3. Téléchargez le pack d\'icônes');
console.log('4. Placez les fichiers dans le dossier /icons/\n');

// Créer le dossier icons s'il n'existe pas
const iconsDir = path.join(__dirname, 'icons');
if (!fs.existsSync(iconsDir)) {
    fs.mkdirSync(iconsDir);
    console.log('✅ Dossier /icons/ créé');
}

// Liste des tailles nécessaires
const REQUIRED_SIZES = [72, 96, 128, 144, 152, 192, 384, 512];

console.log('\n📐 Tailles d\'icônes requises :');
REQUIRED_SIZES.forEach(size => {
    const filename = `icon-${size}x${size}.png`;
    const filepath = path.join(iconsDir, filename);
    const exists = fs.existsSync(filepath);
    
    console.log(`   ${exists ? '✅' : '❌'} ${filename} ${exists ? '(trouvé)' : '(manquant)'}`);
});

// Vérification
const missingIcons = REQUIRED_SIZES.filter(size => 
    !fs.existsSync(path.join(iconsDir, `icon-${size}x${size}.png`))
);

if (missingIcons.length > 0) {
    console.log('\n⚠️  Icônes manquantes détectées !');
    console.log('\n🔧 Solutions :');
    console.log('   Option 1 : Utilisez PWABuilder (recommandé)');
    console.log('   Option 2 : Créez manuellement avec GIMP/Photoshop');
    console.log('   Option 3 : Utilisez ce placeholder temporaire\n');
    
    // Créer des placeholders SVG
    console.log('📝 Création de placeholders temporaires...\n');
    
    REQUIRED_SIZES.forEach(size => {
        const filename = `icon-${size}x${size}.png`;
        const filepath = path.join(iconsDir, filename);
        
        if (!fs.existsSync(filepath)) {
            // Créer un SVG simple
            const svg = `
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  <rect width="${size}" height="${size}" fill="#2e7d32"/>
  <text x="50%" y="50%" font-family="Arial" font-size="${size/4}" fill="white" 
        text-anchor="middle" dominant-baseline="middle" font-weight="bold">NBFO</text>
</svg>`;
            
            // Note : En production, il faudrait convertir SVG → PNG
            // Pour l'instant, on sauvegarde le SVG
            const svgPath = filepath.replace('.png', '.svg');
            fs.writeFileSync(svgPath, svg.trim());
            console.log(`   ✅ Placeholder créé : ${filename.replace('.png', '.svg')}`);
        }
    });
    
    console.log('\n⚠️  ATTENTION : Les fichiers .svg ne sont PAS valides pour les PWA !');
    console.log('   Convertissez-les en .png avec un outil en ligne :\n');
    console.log('   → https://cloudconvert.com/svg-to-png\n');
    
} else {
    console.log('\n✅ Toutes les icônes sont présentes !\n');
}

// Guide final
console.log('═══════════════════════════════════════════════\n');
console.log('📚 Prochaine étape :');
console.log('   Lancez le serveur HTTPS et testez la PWA\n');
console.log('   $ npm install -g http-server');
console.log('   $ http-server -S -p 8443\n');
console.log('═══════════════════════════════════════════════\n');
