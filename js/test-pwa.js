#!/usr/bin/env node
// test-pwa.js - Script de vérification automatique de la PWA NBFO

const fs = require('fs');
const path = require('path');

console.log(`
╔═══════════════════════════════════════════════════╗
║   🧪 Tests de Vérification PWA NBFO               ║
╚═══════════════════════════════════════════════════╝
`);

let totalTests = 0;
let passedTests = 0;

function test(description, condition) {
    totalTests++;
    const status = condition ? '✅ PASS' : '❌ FAIL';
    console.log(`${status} - ${description}`);
    if (condition) passedTests++;
    return condition;
}

console.log('\n📂 Test 1 : Fichiers Essentiels\n');

const essentialFiles = [
    'index.html',
    'dashboard.html',
    'manifest.json',
    'service-worker.js',
    'js/db-local.js',
    'js/api-mock.js',
    'js/ui-utils.js'
];

essentialFiles.forEach(file => {
    test(`Fichier ${file} existe`, fs.existsSync(path.join(__dirname, file)));
});

console.log('\n🎨 Test 2 : Icônes PWA\n');

const requiredIcons = [72, 96, 128, 144, 152, 192, 384, 512];
requiredIcons.forEach(size => {
    const iconPath = path.join(__dirname, 'icons', `icon-${size}x${size}.png`);
    test(`Icône ${size}x${size} existe`, fs.existsSync(iconPath));
});

console.log('\n📄 Test 3 : Validation manifest.json\n');

try {
    const manifestPath = path.join(__dirname, 'manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    
    test('manifest.json est valide JSON', true);
    test('manifest.json contient "name"', !!manifest.name);
    test('manifest.json contient "start_url"', !!manifest.start_url);
    test('manifest.json contient "display"', !!manifest.display);
    test('manifest.json contient "icons"', Array.isArray(manifest.icons) && manifest.icons.length > 0);
    test('manifest.json a au moins une icône 192x192', 
        manifest.icons.some(icon => icon.sizes === '192x192'));
    test('manifest.json a au moins une icône 512x512', 
        manifest.icons.some(icon => icon.sizes === '512x512'));
} catch (err) {
    test('manifest.json est valide JSON', false);
    console.log(`   ⚠️  Erreur: ${err.message}`);
}

console.log('\n🔧 Test 4 : Service Worker\n');

try {
    const swPath = path.join(__dirname, 'service-worker.js');
    const swContent = fs.readFileSync(swPath, 'utf8');
    
    test('Service Worker contient "install"', swContent.includes('install'));
    test('Service Worker contient "activate"', swContent.includes('activate'));
    test('Service Worker contient "fetch"', swContent.includes('fetch'));
    test('Service Worker gère le cache', swContent.includes('caches'));
} catch (err) {
    test('Service Worker est lisible', false);
}

console.log('\n🗄️ Test 5 : Base de Données Locale\n');

try {
    const dbPath = path.join(__dirname, 'js', 'db-local.js');
    const dbContent = fs.readFileSync(dbPath, 'utf8');
    
    test('db-local.js définit IndexedDB', dbContent.includes('indexedDB'));
    test('db-local.js crée les tables', dbContent.includes('objectStore'));
    test('db-local.js exporte DBLocal', dbContent.includes('window.DBLocal'));
    test('db-local.js contient seedDemoData', dbContent.includes('seedDemoData'));
} catch (err) {
    test('db-local.js est lisible', false);
}

console.log('\n🌐 Test 6 : API Mock\n');

try {
    const apiPath = path.join(__dirname, 'js', 'api-mock.js');
    const apiContent = fs.readFileSync(apiPath, 'utf8');
    
    test('api-mock.js intercepte fetch', apiContent.includes('window.fetch'));
    test('api-mock.js gère /api/login', apiContent.includes('/api/login') || apiContent.includes('login'));
    test('api-mock.js gère /api/lots', apiContent.includes('/api/lots'));
    test('api-mock.js gère /api/admissions', apiContent.includes('/api/admissions'));
} catch (err) {
    test('api-mock.js est lisible', false);
}

console.log('\n📱 Test 7 : Configuration HTML\n');

try {
    const indexPath = path.join(__dirname, 'index.html');
    const indexContent = fs.readFileSync(indexPath, 'utf8');
    
    test('index.html référence manifest.json', indexContent.includes('manifest.json'));
    test('index.html a un meta theme-color', indexContent.includes('theme-color'));
    test('index.html charge db-local.js', indexContent.includes('db-local.js'));
    test('index.html charge api-mock.js', indexContent.includes('api-mock.js'));
    test('index.html a un meta viewport', indexContent.includes('viewport'));
} catch (err) {
    test('index.html est lisible', false);
}

console.log('\n');
console.log('═'.repeat(50));
console.log(`\n📊 Résultats : ${passedTests}/${totalTests} tests réussis\n`);

if (passedTests === totalTests) {
    console.log('🎉 FÉLICITATIONS ! Tous les tests sont passés !\n');
    console.log('✅ Votre PWA est prête à être déployée.\n');
    console.log('📚 Prochaines étapes :');
    console.log('   1. Générez les icônes : node generate-icons.js');
    console.log('   2. Testez en local : npm start');
    console.log('   3. Testez en HTTPS : npm run start:https');
    console.log('   4. Déployez : npm run deploy:netlify\n');
} else {
    const failures = totalTests - passedTests;
    console.log(`⚠️  ${failures} test(s) ont échoué.\n`);
    console.log('🔧 Actions recommandées :');
    console.log('   1. Vérifiez les fichiers manquants');
    console.log('   2. Consultez le GUIDE_INSTALLATION.md');
    console.log('   3. Relancez ce script après corrections\n');
}

console.log('═'.repeat(50) + '\n');

// Exit avec le bon code
process.exit(passedTests === totalTests ? 0 : 1);
