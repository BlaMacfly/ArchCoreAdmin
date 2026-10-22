//! Banc d'essai d'ArchCoreAdmin dans le moteur d'AddOns d'ArchRust, sans affichage : on rejoue
//! une session (entrée en jeu, sonde du niveau MJ, réponses d'ArchCore, clics) et on vérifie
//! les commandes que l'AddOn envoie au client.
use archrust_addons::{AddonManager, HostCommand, PointerInput, UnitInfo};
use std::path::PathBuf;

fn unit(cid: i32, name: &str, x: f32, z: f32) -> UnitInfo {
    UnitInfo { cid, tid: 96, name: name.into(), level: 10, hp: Some(100), position: [x, 4600.0, z], ..Default::default() }
}

fn slashes(mgr: &AddonManager) -> Vec<String> {
    mgr.drain_commands()
        .into_iter()
        .filter_map(|c| match c {
            HostCommand::Slash(s) => Some(s),
            HostCommand::Chat { message, .. } => Some(format!("CHAT:{message}")),
            _ => None,
        })
        .collect()
}

fn eval(mgr: &AddonManager, src: &str) -> String {
    mgr.eval_string(src).unwrap_or_else(|e| panic!("{src} : {e}"))
}

fn frame_ui(mgr: &AddonManager) {
    for _ in 0..3 {
        mgr.update(0.3);
        mgr.layout(1280.0, 720.0, &|f| f.estimated_text_size());
    }
}

fn click_at(mgr: &AddonManager, lua_frame: &str) {
    let s = eval(mgr, &format!("(function() local x, y = {lua_frame}:GetCenter() return x .. ',' .. y end)()"));
    let (a, b) = s.split_once(',').unwrap();
    let (x, y) = (a.parse::<f32>().unwrap(), b.parse::<f32>().unwrap());
    for (pressed, released) in [(vec!["LeftButton"], vec![]), (vec![], vec!["LeftButton"])] {
        mgr.pointer(&PointerInput {
            pos: Some((x, y)),
            pressed: pressed.into_iter().map(String::from).collect(),
            released: released.into_iter().map(String::from).collect(),
            wheel: 0.0,
            native_over: false,
        });
    }
}

fn check(label: &str, ok: bool) {
    println!("{} {label}", if ok { "OK  " } else { "ÉCHEC" });
    if !ok {
        std::process::exit(1);
    }
}

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let sv = root.join("sv");
    let _ = std::fs::remove_dir_all(&sv);
    let mut mgr = AddonManager::new(&sv).unwrap();
    let me = unit(1, "Testeur", -475955.0, -66219.0);
    mgr.set_host(|h| {
        h.player = Some(me.clone());
        h.screen = (1280.0, 720.0);
    });
    // Le dossier « ArchCore Admin » contient l'AddOn (ArchCoreAdmin/ArchCoreAdmin.toc).
    mgr.load_dir(&root.join("../..")).unwrap();
    for a in mgr.addons() {
        check(&format!("chargement de {} ({:?})", a.manifest.name, a.error), a.loaded && a.error.is_none());
    }
    mgr.sync_world(
        Some(me.clone()),
        vec![
            unit(2, "Grokk", -475000.0, -66000.0),
            unit(0x4000_0003, "Darryl", -475500.0, -66100.0),
            unit(0x5000_0001, "Ver vert", -474000.0, -65000.0),
        ],
        Some(vec![]),
    );
    mgr.fire_event("PLAYER_LOGIN", &[]);
    mgr.fire("PLAYER_ENTERING_WORLD", (true, false));
    frame_ui(&mgr);
    check(&format!("pas d'erreur Lua au chargement {:?}", mgr.errors()), mgr.errors().is_empty());

    // 1. Sonde du niveau MJ : « /SetExp » sans argument, réponse masquée.
    let sent = slashes(&mgr);
    check(&format!("sonde envoyée {sent:?}"), sent == vec!["/SetExp".to_string()]);
    let hidden = mgr.filter_chat("CHAT_MSG_SAY", "Niveau MJ 3 requis pour /SetExp (le vôtre : 2).", "");
    check("réponse de la sonde masquée", hidden.is_none());
    check("niveau MJ 2 exact", eval(&mgr, "ArchCoreAdmin.gmLevel .. tostring(ArchCoreAdmin.gmLevelExact)") == "2true");
    check("niveau requis appris", eval(&mgr, "ArchCoreAdmin:RequiredLevel('SetExp')") == "3");

    // 2. Commandes : construction et contrôle du niveau.
    check("ligne /create", eval(&mgr, "ArchCoreAdmin:Build('create', {'Testeur', 190, 5, 0})") == r#"/create "Testeur" 190 5 0"#);
    check("ligne /move", eval(&mgr, "ArchCoreAdmin:Build('move', {{'-475955', '-66219.4'}})") == "/move -475955,-66219");
    check("ligne /SetExp 1.5", eval(&mgr, "ArchCoreAdmin:Build('SetExp', {'1,5'})") == "/SetExp 1.5");
    check("ligne /SetExp 2.0", eval(&mgr, "ArchCoreAdmin:Build('SetExp', {2})") == "/SetExp 2.0");
    check("ligne /level sans nom", eval(&mgr, "ArchCoreAdmin:Build('level', {50, ''})") == "/level 50");
    check("nom avec guillemet refusé", eval(&mgr, "select(2, ArchCoreAdmin:Build('kill', {'a\"b'}))").contains("guillemet"));
    check("argument manquant", eval(&mgr, "select(2, ArchCoreAdmin:Build('chatban', {'Grokk'}))").contains("Syntaxe"));
    check("facultatif puis argument refusé", eval(&mgr, "tostring(ArchCoreAdmin:Build('create', {'A', 1, '', 1}))") == "nil");
    eval(&mgr, "tostring(ArchCoreAdmin:Run('level', {50, 'Grokk'}))");
    check("/level bloqué au niveau 2", slashes(&mgr).is_empty());
    check("bouton /level grisé", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'level' then return tostring(b:IsEnabled()) end end end)()") == "false");
    check("bouton /kill actif", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'kill' then return tostring(b:IsEnabled()) end end end)()") == "true");

    // 3. Niveau 3 ou plus : la sonde répond par une erreur de syntaxe.
    eval(&mgr, "ArchCoreAdmin:ProbeLevel() return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "/SetExp : argument manquant. Syntaxe : /SetExp <taux>", "");
    check("niveau 3 ou plus", eval(&mgr, "ArchCoreAdmin:LevelText()").contains("3"));
    eval(&mgr, "ArchCoreAdmin:Run('money', {1000, 'Grokk'}) return ''");
    check("/money envoyé", slashes(&mgr) == vec![r#"/money 1000 "Grokk""#.to_string()]);

    // 4. Confirmation : /kill attend le clic sur « Oui ».
    eval(&mgr, "ArchCoreAdmin:Run('kill', {'Grokk'}) return ''");
    check("/kill retenu avant confirmation", slashes(&mgr).is_empty());
    frame_ui(&mgr);
    check("fenêtre de confirmation", eval(&mgr, "StaticPopup1Text:GetText()").contains(r#"/kill "Grokk""#));
    click_at(&mgr, "StaticPopup1Button1");
    check("/kill envoyé après « Oui »", slashes(&mgr) == vec![r#"/kill "Grokk""#.to_string()]);
    check("réponse /kill visible", mgr.filter_chat("CHAT_MSG_SAY", "Grokk a été tué.", "").is_some());

    // 5. Réponses lues : taux, objet appris, invincibilité.
    eval(&mgr, "ArchCoreAdmin:Run('GetExp') return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "Taux d'expérience : 2.0", "");
    check("taux d'expérience lu", eval(&mgr, "ArchCoreAdmin.rates.exp") == "2.0");
    eval(&mgr, "ArchCoreAdmin:Run('SetUniqueDrop', {3}) return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "Taux de butin unique réglé à 3.0.", "");
    check("taux de butin unique lu", eval(&mgr, "ArchCoreAdmin.rates.uniqueDrop") == "3.0");
    eval(&mgr, "ArchCoreAdmin:Run('create', {'Testeur', 190, 5}) return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "5 × Potion de vie (TID 190) donné(s) à Testeur.", "");
    check("nom d'objet appris", eval(&mgr, "ArchCoreAdmin.db.global.itemNames[190]") == "Potion de vie");
    eval(&mgr, "ArchCoreAdmin:Run('invincible', {1}) return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "Invincibilité activée : les monstres ne vous blessent plus.", "");
    check("invincibilité lue", eval(&mgr, "tostring(ArchCoreAdmin.invincible)") == "true");
    check("message étranger laissé passer", mgr.filter_chat("CHAT_MSG_SAY", "Bienvenue sur ArchCore", "").is_some());
    check("discussion d'un joueur ignorée", mgr.filter_chat("CHAT_MSG_SAY", "Taux d'or : 9.0", "Grokk").is_some() && eval(&mgr, "tostring(ArchCoreAdmin.rates.gold)") == "nil");
    eval(&mgr, "ArchCoreAdmin:Run('GetGold') return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SYSTEM", "Taux d'or : 1.5", "");
    check("réponse en CHAT_MSG_SYSTEM lue aussi", eval(&mgr, "ArchCoreAdmin.rates.gold") == "1.5");
    check("journal rempli", eval(&mgr, "#ArchCoreAdmin.db.char.log").parse::<i32>().unwrap() >= 10);

    // 6. Cibles : personnage, PNJ, monstre.
    mgr.set_target(Some(2));
    check("cible personnage", eval(&mgr, "tostring((ArchCoreAdmin:TargetPlayerName()))") == "Grokk");
    mgr.set_target(Some(0x4000_0003));
    check("cible PNJ ignorée", eval(&mgr, "tostring((ArchCoreAdmin:TargetPlayerName()))") == "nil");
    check("joueurs en vue", eval(&mgr, "table.concat(ArchCoreAdmin:PlayersInView(), ',')") == "Grokk");

    // 7. Commande libre et commande slash de l'AddOn.
    eval(&mgr, "ArchCoreAdmin:RunFree('SetExp 2\\n/kill') return ''");
    check("commande libre sur une ligne", slashes(&mgr) == vec!["/SetExp 2 /kill".to_string()]);
    check("/aca send", mgr.run_slash("/aca send GetGold"));
    check("/aca send envoyé", slashes(&mgr) == vec!["/GetGold".to_string()]);

    // 8. Fenêtre : tous les onglets s'affichent ; clics à la souris.
    check("/aca ouvre", mgr.run_slash("/aca"));
    frame_ui(&mgr);
    check("fenêtre affichée", eval(&mgr, "tostring(ArchCoreAdminFrame:IsShown())") == "true");
    // Mise en page : chaque élément visible tient dans la fenêtre et ne chevauche pas un autre
    // (les listes contiennent leurs lignes : on ne compare que les enfants directs de la page).
    let overlap_lua = r#"(function()
      local f = ArchCoreAdminFrame
      local fl, fb, fw, fh = f:GetRect()
      local items, out = {}, {}
      local page
      for _, s in ipairs(ArchCoreAdmin.sections) do if s.page:IsShown() then page = s.page end end
      local function add(o, label)
        if not o:IsShown() then return end
        local l, b, w, h = o:GetRect()
        if not l then return end
        if o.GetObjectType and o:GetObjectType() == "FontString" then
          w = math.min(o:GetStringWidth(), o:GetWidth() > 0 and o:GetWidth() or 9999)
        end
        if o.GetObjectType and o:GetObjectType() == "CheckButton" then w = w + 4 + o.Text:GetStringWidth() end
        items[#items + 1] = { l = l, b = b, r = l + w, t = b + h, n = o:GetObjectType() .. "[" .. tostring(o.GetText and o:GetText()) .. "]@" .. math.floor(l - fl) .. "," .. math.floor(fb + fh - b - h) .. " w" .. math.floor(w) .. " h" .. math.floor(h) }
        if l < fl - 1 or l + w > fl + fw + 1 or b < fb - 1 or b + h > fb + fh + 1 then
          out[#out + 1] = "déborde: " .. tostring(items[#items].n)
        end
      end
      for _, c in ipairs({ page:GetChildren() }) do add(c) end
      for _, r in ipairs({ page:GetRegions() }) do add(r) end
      for i = 1, #items do for j = i + 1, #items do
        local a, b = items[i], items[j]
        if a.l < b.r - 1 and b.l < a.r - 1 and a.b < b.t - 1 and b.b < a.t - 1 then
          out[#out + 1] = tostring(a.n) .. " / " .. tostring(b.n)
        end
      end end
      return table.concat(out, " | ")
    end)()"#;
    for key in ["gm", "players", "items", "teleport", "server", "log"] {
        check(&format!("onglet {key}"), mgr.run_slash(&format!("/aca {key}")));
        frame_ui(&mgr);
        let o = eval(&mgr, overlap_lua);
        println!("     mise en page {key} : {}", if o.is_empty() { "propre".into() } else { o });
    }
    check(&format!("pas d'erreur Lua dans les onglets {:?}", mgr.errors()), mgr.errors().is_empty());
    // Onglet Téléport : clic sur « Téléporter » avec la position remplie à l'ouverture.
    mgr.run_slash("/aca teleport");
    frame_ui(&mgr);
    slashes(&mgr);
    let go = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'move' then return b end end end)()";
    click_at(&mgr, go);
    let sent = slashes(&mgr);
    check(&format!("clic Téléporter {sent:?}"), sent == vec!["/move -475955,-66219".to_string()]);
    // Onglet Serveur : « Tout lire » envoie 7 demandes.
    mgr.run_slash("/aca server");
    frame_ui(&mgr);
    let all = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b:GetText() == 'Tout lire' or b:GetText() == 'Read all' then return b end end end)()";
    click_at(&mgr, all);
    check("Tout lire", slashes(&mgr).len() == 7);
    // Libellés des taux remplis dans l'onglet Serveur.
    for (msg, _) in [("Taux d'expérience : 2.0", 0), ("Taux d'or : 1.0", 0)] {
        mgr.filter_chat("CHAT_MSG_SAY", msg, "");
    }
    frame_ui(&mgr);
    println!("langue : {}", eval(&mgr, "GetLocale()"));

    // 9. Compte sans droits : tout est grisé.
    eval(&mgr, "ArchCoreAdmin:ProbeLevel() return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "Commande inconnue : /SetExp", "");
    check("niveau 0", eval(&mgr, "ArchCoreAdmin.gmLevel") == "0");
    check("boutons grisés", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b:IsEnabled() then return b.command end end return 'aucun' end)()") == "aucun");
    check(&format!("pas d'erreur Lua {:?}", mgr.errors()), mgr.errors().is_empty());

    mgr.save_all().unwrap();
    let saved = std::fs::read_to_string(sv.join("ArchCoreAdmin.lua")).unwrap_or_default();
    check("SavedVariables écrites", saved.contains("Anchorville") && saved.contains("Potion de vie"));
    println!("--- {} octets de SavedVariables", saved.len());
}
