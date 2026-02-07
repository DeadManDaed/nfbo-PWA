// public/js/users.js

async function ouvrirModalUtilisateur() {
    // 1. Charger les magasins pour pouvoir les assigner au nouvel utilisateur
    const res = await fetch('/api/magasins');
    const magasins = await res.json();
    
    const selectMag = document.getElementById('user-magasin-select');
    if (selectMag) {
        selectMag.innerHTML = '<option value="">-- Assigner un magasin --</option>' + 
            magasins.map(m => `<option value="${m.id}">${m.nom}</option>`).join('');
    }

    document.getElementById('modal-utilisateur').style.display = 'block';
}

const formUser = document.getElementById('form-creer-utilisateur');
if (formUser) { // On ne lie l'événement QUE si le formulaire est présent à l'écran
    formUser.onsubmit = async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    
    const payload = {
        nom: formData.get('nom'),
        role: formData.get('role'), // 'administrateur', 'auditeur', 'magasinier'
        magasin_id: parseInt(formData.get('magasin_id')),
        password: formData.get('password') // À hacher côté serveur !
    };

    const res = await fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    if (res.ok) {
        alert("Utilisateur créé avec succès");
        e.target.reset();
        document.getElementById('modal-utilisateur').style.display = 'none';
        refreshAdminTable('utilisateurs'); // Recharge la liste
    } else {
        alert("Erreur lors de la création");
    }
};
}
