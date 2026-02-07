// --- public/js/messages.js : LOGIQUE DE MESSAGERIE (API-based) ---

// 1. Charger la boîte de réception
async function loadInbox() {
    const list = document.getElementById('inbox-list');
    try {
        const res = await fetch('/api/messages');
        const messages = await res.json();
        
        if (messages.length === 0) {
            list.innerHTML = "<p style='text-align:center; color:#999;'>Aucun message.</p>";
            return;
        }

        list.innerHTML = messages.map(msg => `
            <div class="message-item ${msg.lu ? '' : 'unread'}" onclick="readMessage(${msg.id})">
                <div class="meta">
                    <span>${msg.expediteur}</span>
                    <span>${new Date(msg.date).toLocaleDateString()}</span>
                </div>
                <div class="subject">${msg.objet}</div>
            </div>
        `).join('');
    } catch (err) {
        list.innerHTML = "<p style='color:red'>Erreur de chargement.</p>";
    }
}

// 2. Lire un message
async function readMessage(id) {
    const display = document.getElementById('message-content-display');
    display.innerHTML = "Chargement...";
    try {
        const res = await fetch(`/api/messages/${id}`);
        const msg = await res.json();
        
        display.innerHTML = `
            <div style="background:white; padding:20px; border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,0.05);">
                <h3 style="margin-top:0;">${msg.objet}</h3>
                <p style="font-size:13px; color:#666;">De: <strong>${msg.expediteur}</strong> | Le ${new Date(msg.date).toLocaleString()}</p>
                <hr style="border:0; border-top:1px solid #eee; margin:15px 0;">
                <div style="line-height:1.6; color:#444;">${msg.contenu}</div>
                <button class="btn" style="margin-top:20px; background:#eee;" onclick="showNewMessageForm('${msg.expediteur_id}', 'Re: ${msg.objet}')">Répondre</button>
            </div>
        `;
    } catch (err) { display.innerHTML = "Erreur de lecture."; }
}

// 3. Formulaire d'envoi
function showNewMessageForm(destId = '', objet = '') {
    const display = document.getElementById('message-content-display');
    display.innerHTML = `
        <form id="sendMessageForm" style="display:flex; flex-direction:column; gap:15px;">
            <h3>Nouveau message</h3>
            <select id="msg-destinataire" required style="padding:10px;">
                <option value="">-- Choisir le destinataire --</option>
                </select>
            <input type="text" id="msg-objet" placeholder="Objet" value="${objet}" required style="padding:10px;">
            <textarea id="msg-contenu" placeholder="Votre message..." rows="8" required style="padding:10px; font-family:inherit;"></textarea>
            <div style="display:flex; gap:10px; justify-content:flex-end;">
                <button type="button" class="btn" onclick="document.getElementById('message-content-display').innerHTML=''">Annuler</button>
                <button type="submit" class="btn" style="background:var(--primary); color:white; padding:10px 30px;">Envoyer</button>
            </div>
        </form>
    `;
    
    // Charger la liste des destinataires (API Utilisateurs + Producteurs)
    loadDestinataires(destId);

    document.getElementById('sendMessageForm').onsubmit = sendMessage;
}

// Remplace loadDestinataires dans public/js/messages.js
async function loadDestinataires(selectedId) {
    const sel = document.getElementById('msg-destinataire');
    const user = getCurrentUser(); 

    try {
        const res = await fetch(`/api/destinataires?role=${user.role}&magasin_id=${user.magasin_id || ''}`);
        const groups = await res.json(); 

        sel.innerHTML = '<option value="">-- Choisir le destinataire --</option>';

        // Groupe Employés
        if (groups.employers?.length > 0) {
            const g = document.createElement('optgroup');
            g.label = "Personnel";
            groups.employers.forEach(u => {
                const opt = new Option(`${u.nom} (${u.role})`, u.id);
                if(u.id == selectedId) opt.selected = true;
                g.appendChild(opt);
            });
            sel.add(g);
        }

        // Groupe Producteurs (Utilise le champ nom_producteur aliasé en nom)
        if (groups.producteurs?.length > 0) {
            const g = document.createElement('optgroup');
            g.label = "Producteurs";
            groups.producteurs.forEach(p => {
                const opt = new Option(p.nom, p.id); // 'nom' est l'alias de 'nom_producteur'
                if(p.id == selectedId) opt.selected = true;
                g.appendChild(opt);
            });
            sel.add(g);
        }
    } catch (err) { console.error("Erreur destinataires", err); }
}

async function sendMessage(e) {
    e.preventDefault();
    const user = getCurrentUser();
    const data = {
        destinataire_id: document.getElementById('msg-destinataire').value,
        objet: document.getElementById('msg-objet').value,
        contenu: document.getElementById('msg-contenu').value
    };

    try {
        const res = await fetch('/api/messages', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-user-id': user.id // On passe l'ID de l'envoyeur
            },
            body: JSON.stringify(data)
        });
        if(res.ok) {
            alert("Message envoyé !");
            loadInbox();
            document.getElementById('message-content-display').innerHTML = "";
        }
    } catch (err) { alert("Erreur lors de l'envoi"); }
}