#!/usr/bin/env node
// migrate-sql-to-json.js - Convertit votre backup PostgreSQL en JSON pour IndexedDB

const fs = require('fs');
const path = require('path');

console.log(`
╔═══════════════════════════════════════════════════╗
║   🔄 Migration PostgreSQL → IndexedDB            ║
╚═══════════════════════════════════════════════════╝
`);

// Chemin vers votre fichier SQL
const SQL_FILE = process.argv[2] || './backup.sql';
const OUTPUT_FILE = './data-migration.json';

if (!fs.existsSync(SQL_FILE)) {
    console.error(`❌ Fichier ${SQL_FILE} introuvable`);
    console.log('\nUsage: node migrate-sql-to-json.js chemin/vers/backup.sql');
    process.exit(1);
}

console.log(`📂 Lecture de ${SQL_FILE}...`);
const sqlContent = fs.readFileSync(SQL_FILE, 'utf8');

// Structure de sortie
const data = {
    users: [],
    admissions: [],
    lots: [],
    producteurs: [],
    magasins: [],
    retraits: [],
    regions: [],
    departements: [],
    arrondissements: [],
    departement_codes: [],
    caisse: [],
    caisse_lignes: [],
    cheques: [],
    paiements: [],
    internal_bank_logs: [],
    employers: [],
    transferts: [],
    audit: [],
    logs_deploiement: [],
    messages: []
};

// Parser les INSERT INTO
function parseInserts(sql, tableName) {
    const regex = new RegExp(`INSERT INTO (?:public\\.)?"?${tableName}"?\\s*(?:\\([^)]+\\))?\\s*VALUES\\s*\\(([^;]+)\\);`, 'gim');
    const matches = [...sql.matchAll(regex)];
    
    console.log(`   Parsing table ${tableName}: ${matches.length} INSERT trouvés`);
    
    return matches.map(match => {
        try {
            // Nettoie et split les valeurs
            const valuesPart = match[1]
                .replace(/\n/g, ' ')
                .replace(/\s+/g, ' ')
                .trim();
            
            // Parse les valeurs (simplifié - peut nécessiter ajustement)
            const values = parseValues(valuesPart);
            return values;
        } catch (e) {
            console.warn(`   ⚠️ Erreur parsing: ${e.message}`);
            return null;
        }
    }).filter(Boolean);
}

// Parser les valeurs d'un INSERT
function parseValues(str) {
    const values = [];
    let current = '';
    let inString = false;
    let stringChar = null;
    let depth = 0;
    
    for (let i = 0; i < str.length; i++) {
        const char = str[i];
        const prev = str[i - 1];
        
        if ((char === "'" || char === '"') && prev !== '\\') {
            if (!inString) {
                inString = true;
                stringChar = char;
            } else if (char === stringChar) {
                inString = false;
                stringChar = null;
            }
            current += char;
        } else if (char === '(' && !inString) {
            depth++;
            current += char;
        } else if (char === ')' && !inString) {
            depth--;
            current += char;
        } else if (char === ',' && !inString && depth === 0) {
            values.push(parseValue(current.trim()));
            current = '';
        } else {
            current += char;
        }
    }
    
    if (current.trim()) {
        values.push(parseValue(current.trim()));
    }
    
    return values;
}

// Convertit une valeur SQL en valeur JavaScript
function parseValue(val) {
    val = val.trim();
    
    // NULL
    if (val === 'NULL' || val === 'null') return null;
    
    // Booléen
    if (val === 'true' || val === 't' || val === "'t'") return true;
    if (val === 'false' || val === 'f' || val === "'f'") return false;
    
    // String entre quotes
    if ((val.startsWith("'") && val.endsWith("'")) || 
        (val.startsWith('"') && val.endsWith('"'))) {
        return val.slice(1, -1)
            .replace(/''/g, "'")
            .replace(/\\'/g, "'")
            .replace(/\\"/g, '"');
    }
    
    // JSONB (ex: '{"key": "value"}')
    if (val.startsWith("'{") && val.endsWith("}'")) {
        try {
            return JSON.parse(val.slice(1, -1));
        } catch (e) {
            return val.slice(1, -1);
        }
    }
    
    // Nombre
    if (!isNaN(val)) {
        return val.includes('.') ? parseFloat(val) : parseInt(val);
    }
    
    // Date/Timestamp
    if (val.match(/^\d{4}-\d{2}-\d{2}/) || val.match(/^'\d{4}-\d{2}-\d{2}/)) {
        return val.replace(/'/g, '');
    }
    
    return val;
}

// Mapper les colonnes (à adapter selon vos tables)
const COLUMN_MAPS = {
    admissions: [
        'id', 'lot_id', 'producteur_id', 'quantite', 'unite', 'prix_ref',
        'date_reception', 'date_expiration', 'magasin_id', 'utilisateur',
        'valeur_totale', 'benefice_estime', 'coef_qualite', 'taux_tax',
        'region_id', 'departement_id', 'arrondissement_id', 'localite',
        'mode_paiement', 'montant_verse', 'grade_qualite', 'user_id'
    ],
    users: ['id', 'username', 'password_hash', 'role', 'magasin_id', 'statut'],
    lots: ['id', 'nom_produit', 'description', 'categorie', 'prix_ref', 'unites_admises'],
    producteurs: ['id', 'nom_producteur', 'tel_producteur', 'region_id', 'adresse'],
    magasins: ['id', 'nom', 'code', 'adresse', 'region_id'],
    retraits: ['id', 'lot_id', 'magasin_id', 'quantite', 'unite', 'type_retrait', 'prix_ref', 'utilisateur'],
    regions: ['id', 'nom', 'code'],
    departements: ['id', 'nom', 'region_id'],
    arrondissements: ['id', 'nom', 'departement_id', 'code'],
    departement_codes: ['departement_id', 'code'],
    caisse: ['id', 'benefices_virtuels'],
    caisse_lignes: ['id', 'caisse_id', 'lot_id', 'producteur_id', 'type_operation', 'montant', 'statut', 'reference'],
    cheques: ['id', 'numero_cheque', 'banque', 'montant', 'emetteur', 'date_enregistrement'],
    paiements: ['id', 'producteur_id', 'montant', 'mode_paiement', 'date_paiement', 'caissier'],
    internal_bank_logs: ['id', 'type_mouvement', 'lot_id', 'admission_id', 'montant_realise', 'prix_acquisition_total', 'prix_sortie_total', 'difference_valeur', 'date_operation', 'utilisateur'],
    employers: ['id', 'magasin_id', 'nom', 'role', 'contact', 'date_embauche', 'statut', 'matricule'],
    transferts: ['id', 'lot_id', 'magasin_depart', 'magasin_dest', 'quantite', 'unite', 'statut', 'chauffeur', 'date_creation'],
    audit: ['id', 'date', 'utilisateur', 'action'],
    logs_deploiement: ['id', 'date_erreur', 'contexte', 'utilisateur', 'role_utilisateur', 'message_erreur', 'etat_formulaire', 'resolu'],
    messages: ['id', 'expediteur', 'destinataire', 'sujet', 'contenu', 'lu', 'date_envoi']
};

// Extraction des données
console.log('\n📊 Extraction des données...\n');

Object.keys(COLUMN_MAPS).forEach(tableName => {
    const rawRows = parseInserts(sqlContent, tableName);
    const columns = COLUMN_MAPS[tableName];
    
    data[tableName] = rawRows.map(values => {
        const obj = {};
        columns.forEach((col, index) => {
            obj[col] = values[index] !== undefined ? values[index] : null;
        });
        return obj;
    });
    
    console.log(`   ✅ ${tableName}: ${data[tableName].length} enregistrements`);
});

// Sauvegarde
console.log(`\n💾 Sauvegarde dans ${OUTPUT_FILE}...`);
fs.writeFileSync(OUTPUT_FILE, JSON.stringify(data, null, 2), 'utf8');

console.log('\n✅ Migration SQL → JSON terminée !');
console.log(`\n📊 Résumé :`);

let totalRecords = 0;
Object.keys(data).forEach(table => {
    const count = data[table].length;
    if (count > 0) {
        console.log(`   ${table.padEnd(25)} : ${count} enregistrements`);
        totalRecords += count;
    }
});

console.log(`\n   TOTAL : ${totalRecords} enregistrements\n`);

console.log('📋 Prochaine étape :');
console.log('   1. Copiez data-migration.json dans votre dossier PWA');
console.log('   2. Ouvrez import-data.html dans le navigateur');
console.log('   3. Cliquez sur "Importer les données"\n');
