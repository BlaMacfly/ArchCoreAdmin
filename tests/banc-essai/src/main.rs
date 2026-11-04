//! Banc d'essai d'ArchCoreAdmin dans le moteur d'AddOns d'ArchRust, sans affichage : on rejoue
//! une session (entrée en jeu, sonde du niveau MJ, réponses d'ArchCore, clics) et on vérifie
//! les commandes que l'AddOn envoie au client.
use archrust_addons::{AddonManager, HostCommand, ItemTemplateInfo, PointerInput, UnitInfo};
use std::path::PathBuf;
use std::sync::Arc;

/// Petit catalogue d'objets, comme celui qu'ArchRust tire d'ItemTemplateAll.ini.
fn catalog() -> Vec<ItemTemplateInfo> {
    let t = |tid: i32, name: &str, item_type: i64, kind: i64, level: i64, icon: &str| ItemTemplateInfo {
        tid,
        name: name.into(),
        icon: icon.into(),
        level,
        item_type,
        kind,
        part: match kind {
            2 => 9,
            4 => 10,
            8 => 11,
            _ => 0,
        },
        stack: if item_type == 1 { 99 } else { 1 },
    };
    vec![
        t(1, "Short Bow", 0, 2, 1, "l00006ba"),
        t(190, "Small Life Potion", 1, 0, 0, "l0000040"),
        t(198, "Passport", 2, 0, 0, "l0000041"),
        t(486, "Reinforcement Potion", 1, 0, 0, "l0000042"),
        t(530, "Lionheart Shield", 0, 4, 55, "l00002f1"),
        t(531, "Steelhorn Shield", 0, 4, 63, "l00002f2"),
        t(532, "Night Shield", 0, 4, 71, ""),
        t(900, "Blood Ring", 0, 8, 30, "l0000100"),
    ]
}

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

/// Lignes de l'info-bulle affichée, séparées par « | ».
fn tooltip_text(mgr: &AddonManager) -> String {
    eval(mgr, "(function() local t = {} for i = 1, GameTooltip._n or 0 do t[i] = _G['GameTooltipTextLeft' .. i]:GetText() end return table.concat(t, ' | ') end)()")
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
        h.item_templates = Arc::new(catalog());
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
    check("boutons /speed actifs au niveau 2", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'speed' and not b:IsEnabled() then return 'non' end end return 'oui' end)()") == "oui");
    check("bouton /additem grisé au niveau 2", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'additem' then return tostring(b:IsEnabled()) end end end)()") == "false");
    check("ligne /speed", eval(&mgr, "ArchCoreAdmin:Build('speed', {' 3 '})") == "/speed 3");
    check("/speed sans valeur refusé", eval(&mgr, "tostring(ArchCoreAdmin:Build('speed', {''}))") == "nil");
    check("ligne /additem", eval(&mgr, "ArchCoreAdmin:Build('additem', {190})") == "/additem 190");

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
    eval(&mgr, "ArchCoreAdmin:Run('speed', {5}) return ''");
    check("/speed envoyé", slashes(&mgr) == vec!["/speed 5".to_string()]);
    mgr.filter_chat("CHAT_MSG_SAY", "Vitesse de déplacement ×5 (course 6000).", "");
    check("vitesse lue", eval(&mgr, "tostring(ArchCoreAdmin.speed)") == "5");
    eval(&mgr, "ArchCoreAdmin:Run('additem', {191, 2}) return ''");
    check("/additem envoyé", slashes(&mgr) == vec!["/additem 191 2".to_string()]);
    mgr.filter_chat("CHAT_MSG_SAY", "2 × Élixir de mana (TID 191) ajouté(s) à votre inventaire.", "");
    check("nom d'objet appris par /additem", eval(&mgr, "ArchCoreAdmin.db.global.itemNames[191]") == "Élixir de mana");
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
    let logo = eval(&mgr, "tostring(ArchCoreAdmin.logo:GetTexture())");
    check(&format!("logo en tête ({logo})"), logo.to_lowercase().contains("logo") && eval(&mgr, "tostring(ArchCoreAdmin.logo:IsVisible())") == "true");
    check("logo dans la fenêtre, au-dessus des onglets", eval(&mgr, "(function() local _, lb, _, lh = ArchCoreAdmin.logo:GetRect() local _, fb, _, fh = ArchCoreAdminFrame:GetRect() local _, tb, _, th = ArchCoreAdmin.sections[1].tab:GetRect() return tostring(lb + lh <= fb + fh and lb >= tb + th) end)()") == "true");
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
    for key in ["gm", "players", "items", "loot", "teleport", "server", "log"] {
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
    // Onglet MJ : clic sur « ×10 ».
    mgr.run_slash("/aca gm");
    frame_ui(&mgr);
    slashes(&mgr);
    click_at(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b:GetText() == '×10' then return b end end end)()");
    let sent = slashes(&mgr);
    check(&format!("clic ×10 {sent:?}"), sent == vec!["/speed 10".to_string()]);
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

    // 9. Objets : catalogue du client, catégories, recherche, choix à la souris, icônes.
    check("catalogue d'objets vu par l'AddOn", eval(&mgr, "tostring(ArchCoreAdmin:HasItemCatalog())") == "true");
    mgr.run_slash("/aca items");
    frame_ui(&mgr);
    let page = "ArchCoreAdmin.sectionsByKey.items.page";
    let rows = |mgr: &AddonManager| eval(mgr, &format!("(function() local t = {{}} for _, it in ipairs({page}.list.items) do t[#t + 1] = it.tid end return table.concat(t, ',') end)()"));
    check(&format!("tous les objets, par niveau requis ({})", rows(&mgr)), rows(&mgr) == "190,198,486,1,900,530,531,532");
    click_at(&mgr, &format!("{page}.categories.armor"));
    frame_ui(&mgr);
    check(&format!("catégorie Armures ({})", rows(&mgr)), rows(&mgr) == "530,531,532");
    click_at(&mgr, &format!("{page}.categories.all"));
    eval(&mgr, &format!("{page}.search:SetText('blood') return ''"));
    frame_ui(&mgr);
    check(&format!("recherche par nom ({})", rows(&mgr)), rows(&mgr) == "900");
    eval(&mgr, &format!("{page}.search:SetText('53') return ''"));
    frame_ui(&mgr);
    check(&format!("recherche par TID ({})", rows(&mgr)), rows(&mgr) == "530,531,532");
    check("icône de la ligne", eval(&mgr, &format!("tostring({page}.list.rows[1].icon.tex:GetTexture())")).to_lowercase().contains("l00002f1"));
    check("ligne sans icône : « ? »", eval(&mgr, &format!("tostring({page}.list.rows[3].icon.none:IsShown())")) == "true");
    click_at(&mgr, &format!("{page}.list.rows[2]"));
    frame_ui(&mgr);
    check("clic sur un objet : TID rempli", eval(&mgr, &format!("{page}.tid:GetText()")) == "531");
    let preview = eval(&mgr, &format!("{page}.previewName:GetText() .. '|' .. {page}.previewInfo:GetText()"));
    check(&format!("aperçu de l'objet choisi ({preview})"), preview.starts_with("Steelhorn Shield|TID 531"));
    check("icône de l'aperçu", eval(&mgr, &format!("tostring({page}.preview.tex:GetTexture())")).to_lowercase().contains("l00002f2"));
    let o = eval(&mgr, overlap_lua);
    check(&format!("mise en page des objets après recherche : {o}"), o.is_empty());
    slashes(&mgr);
    click_at(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'additem' then return b end end end)()");
    let sent = slashes(&mgr);
    check(&format!("/additem de l'objet choisi {sent:?}"), sent == vec!["/additem 531 1".to_string()]);
    eval(&mgr, &format!("{page}.label:SetText('Mon bouclier') return ''"));
    click_at(&mgr, &format!("{page}.addFavorite"));
    click_at(&mgr, &format!("{page}.categories.favorites"));
    frame_ui(&mgr);
    check(&format!("favoris ({})", rows(&mgr)), rows(&mgr) == "531" && eval(&mgr, &format!("{page}.list.rows[1].text:GetText()")) == "Mon bouclier");

    // 9 bis. Survol d'un objet (point 05) : ce que le client donne aujourd'hui, partie du corps comprise.
    click_at(&mgr, &format!("{page}.categories.armor"));
    frame_ui(&mgr);
    eval(&mgr, &format!("local r = {page}.list.rows[1] r:GetScript('OnEnter')(r) return ''"));
    let tip = tooltip_text(&mgr);
    check(&format!("info-bulle d'un objet : {tip}"), tip.contains("Lionheart Shield") && tip.contains("TID 530") && tip.contains("Niveau requis 55") && tip.contains("Se porte : main droite"));
    eval(&mgr, &format!("local r = {page}.list.rows[1] r:GetScript('OnLeave')(r) return ''"));
    check("sans les tables du serveur : pas de filtre de classe", eval(&mgr, &format!("tostring({page}.classButton:IsShown())")) == "false");
    check("note : le catalogue du client compte les ajouts d'Archonia", eval(&mgr, &format!("{page}.note:GetText()")).contains("Archonia"));

    // 9 ter. Objet qui ne peut pas être donné (point 14) : refus du serveur, silence, succès.
    let result = |mgr: &AddonManager| eval(mgr, &format!("{page}.status:IsShown() and {page}.status:GetText() or ''"));
    let create = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'create' then return b end end end)()";
    eval(&mgr, &format!("{page}.tid:SetText('530') return ''"));
    slashes(&mgr);
    click_at(&mgr, create);
    check("/create envoyé", slashes(&mgr) == vec![r#"/create "Testeur" 530 1 0"#.to_string()]);
    check(&format!("attente affichée ({})", result(&mgr)), result(&mgr).contains("en attente") && eval(&mgr, &format!("tostring({page}.note:IsShown())")) == "false");
    mgr.filter_chat("CHAT_MSG_SAY", r#"/create : objet inconnu : TID 530. Syntaxe : /create "nom" <TID> <quantité> <0|1>"#, "");
    let refused = result(&mgr);
    check(&format!("refus expliqué, avec le nom de l'objet ({refused})"), refused.contains("Lionheart Shield (TID 530)") && refused.contains("épisode 8") && refused.contains("Archonia"));
    check("refus noté au journal", eval(&mgr, "ArchCoreAdmin.db.char.log[#ArchCoreAdmin.db.char.log - 1].k") == "!");
    eval(&mgr, "ArchCoreAdmin:Run('create', {'Absent', 530, 1, 0}) return ''");
    mgr.filter_chat("CHAT_MSG_SAY", r#"/create : personnage introuvable : Absent. Syntaxe : /create "nom" <TID> <quantité> <0|1>"#, "");
    check(&format!("personnage introuvable ({})", result(&mgr)), result(&mgr).contains("Personnage introuvable : Absent"));
    eval(&mgr, "ArchCoreAdmin:Run('create', {'Testeur', 530, 1, 0}) return ''");
    mgr.filter_chat("CHAT_MSG_SAY", r#"/create : inventaire plein pour Testeur. Syntaxe : /create "nom" <TID> <quantité> <0|1>"#, "");
    check(&format!("inventaire plein ({})", result(&mgr)), result(&mgr).contains("Inventaire plein"));
    let additem = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'additem' then return b end end end)()";
    eval(&mgr, &format!("{page}.tid:SetText('15151') return ''"));
    slashes(&mgr);
    click_at(&mgr, additem);
    check("/additem d'un TID hors catalogue", slashes(&mgr) == vec!["/additem 15151 1".to_string()]);
    mgr.update(6.0);
    let silence = result(&mgr);
    check(&format!("silence du serveur expliqué ({silence})"), silence.contains("TID 15151") && silence.contains("ne répond pas") && silence.contains("Archonia"));
    check(&format!("pas d'erreur Lua (refus) {:?}", mgr.errors()), mgr.errors().is_empty());
    let o = eval(&mgr, overlap_lua);
    check(&format!("mise en page avec la ligne d'état : {o}"), o.is_empty());
    eval(&mgr, &format!("{page}.tid:SetText('190') return ''"));
    slashes(&mgr);
    click_at(&mgr, additem);
    mgr.filter_chat("CHAT_MSG_SAY", "1 × Small Life Potion (TID 190) ajouté(s) à votre inventaire.", "");
    check(&format!("objet donné affiché ({})", result(&mgr)), result(&mgr).contains("Small Life Potion"));
    mgr.update(6.0);
    check("réponse reçue : pas de faux silence", result(&mgr).contains("Small Life Potion"));
    eval(&mgr, &format!("{page}.qty:SetText('10000') return ''"));
    slashes(&mgr);
    click_at(&mgr, additem);
    check("quantité hors limites : rien d'envoyé", slashes(&mgr).is_empty() && result(&mgr).contains("9999"));
    eval(&mgr, &format!("{page}.qty:SetText('1') return ''"));
    click_at(&mgr, &format!("{page}.list.rows[1]"));
    check("choisir un objet efface l'état, la note revient", result(&mgr).is_empty() && eval(&mgr, &format!("tostring({page}.note:IsShown())")) == "true");

    // 10. Simulateur de butin : /simloot et lecture de la réponse (en-tête puis une ligne par objet).
    mgr.run_slash("/aca loot");
    frame_ui(&mgr);
    let loot = "ArchCoreAdmin.sectionsByKey.loot.page";

    // 10 bis. Choix du monstre (point 06) : ceux rencontrés, recherche par nom, clic.
    let monsters = |mgr: &AddonManager| eval(mgr, &format!("(function() local t = {{}} for _, m in ipairs({loot}.monsters.items) do t[#t + 1] = m.tid .. ':' .. m.name end return table.concat(t, ',') end)()"));
    check(&format!("monstre en vue listé ({})", monsters(&mgr)), monsters(&mgr) == "96:Ver vert");
    check("la liste s'ouvre sans résultat à montrer", eval(&mgr, &format!("{loot}.view")) == "monsters");
    check("note : monstres rencontrés", eval(&mgr, &format!("(function() for _, r in ipairs({{ {loot}:GetRegions() }}) do local s = r.GetText and r:GetText() if r:IsShown() and s and s:find('rencontrés', 1, true) then return 'oui' end end return 'non' end)()")) == "oui");
    let o = eval(&mgr, overlap_lua);
    check(&format!("mise en page des monstres : {o}"), o.is_empty());
    mgr.sync_world(
        Some(me.clone()),
        vec![
            unit(2, "Grokk", -475000.0, -66000.0),
            unit(0x5000_0001, "Ver vert", -474000.0, -65000.0),
            UnitInfo { cid: 0x5000_0002, tid: 451, name: "Loup gris".into(), level: 1, hp: Some(50), position: [-474500.0, 4600.0, -65500.0], ..Default::default() },
        ],
        None,
    );
    frame_ui(&mgr);
    check(&format!("monstre apparu en vue : ajouté à la liste ({})", monsters(&mgr)), monsters(&mgr) == "451:Loup gris,96:Ver vert");
    eval(&mgr, &format!("{loot}.monsterSearch:SetText('LOUP') return ''"));
    frame_ui(&mgr);
    check(&format!("recherche d'un monstre par nom ({})", monsters(&mgr)), monsters(&mgr) == "451:Loup gris");
    eval(&mgr, &format!("{loot}.monsterSearch:SetText('9') return ''"));
    check(&format!("recherche d'un monstre par TID ({})", monsters(&mgr)), monsters(&mgr) == "96:Ver vert");
    eval(&mgr, &format!("{loot}.monsterSearch:SetText('') return ''"));
    frame_ui(&mgr);
    click_at(&mgr, &format!("{loot}.monsters.rows[1]"));
    frame_ui(&mgr);
    check("clic sur un monstre : TID et nom remplis", eval(&mgr, &format!("{loot}.tid:GetText() .. '|' .. {loot}.monsterName:GetText()")) == "451|Loup gris");
    eval(&mgr, &format!("local r = {loot}.monsters.rows[1] r:GetScript('OnEnter')(r) return ''"));
    let tip = tooltip_text(&mgr);
    check(&format!("info-bulle d'un monstre : {tip}"), tip.contains("Loup gris") && tip.contains("TID 451") && tip.contains("En vue"));
    eval(&mgr, &format!("local r = {loot}.monsters.rows[1] r:GetScript('OnLeave')(r) return ''"));
    mgr.set_target(Some(0x5000_0001));
    let target = "(function() for _, b in ipairs({ ArchCoreAdmin.sectionsByKey.loot.page:GetChildren() }) do if b:GetObjectType() == 'Button' and b.tipText and b.tipText:find('monstre ciblé', 1, true) then return b end end end)()";
    click_at(&mgr, target);
    check("bouton Cible : TID du monstre ciblé", eval(&mgr, &format!("{loot}.tid:GetText() .. '|' .. {loot}.monsterName:GetText()")) == "96|Ver vert");
    mgr.set_target(None);
    let sim_btn = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'simloot' then return b end end end)()";
    // Refus et silence de /simloot : le résumé le dit au lieu de rester sur « envoyée ».
    eval(&mgr, &format!("local p = {loot} p.tid:SetText('99999') return ''"));
    slashes(&mgr);
    click_at(&mgr, sim_btn);
    slashes(&mgr);
    check("/simloot : la vue passe au résultat", eval(&mgr, &format!("{loot}.view")) == "results");
    mgr.filter_chat("CHAT_MSG_SAY", "/simloot : monstre inconnu : TID 99999. Syntaxe : /simloot <TID du monstre> <nombre> [taux de butin] [taux d'or]", "");
    let s = eval(&mgr, &format!("{loot}.summary:GetText()"));
    check(&format!("refus de /simloot expliqué ({s})"), s.contains("TID 99999") && s.contains("rien n'a été simulé"));
    click_at(&mgr, sim_btn);
    slashes(&mgr);
    mgr.update(6.0);
    let s = eval(&mgr, &format!("{loot}.summary:GetText()"));
    check(&format!("silence de /simloot expliqué ({s})"), s.contains("ne répond pas"));
    let o = eval(&mgr, overlap_lua);
    check(&format!("mise en page du résultat : {o}"), o.is_empty());

    eval(&mgr, &format!("local p = {loot} p.tid:SetText('450') p.kills:SetText('500') p.drop:SetText('2') return ''"));
    slashes(&mgr);
    let sim = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'simloot' then return b end end end)()";
    click_at(&mgr, sim);
    let sent = slashes(&mgr);
    check(&format!("/simloot envoyé {sent:?}"), sent == vec!["/simloot 450 500 2.0".to_string()]);
    let head = "Butin simulé : 500 × Green Worm (TID 450, niveau 1), taux de butin 2.0, taux d'or 1.0, tueur niveau 50 : 6123 pièce(s) d'or, 39 objet(s) en 2 sorte(s).";
    mgr.filter_chat("CHAT_MSG_SAY", head, "");
    check("en-tête lu", eval(&mgr, "ArchCoreAdmin.sim.kinds .. '|' .. ArchCoreAdmin.sim.gold .. '|' .. ArchCoreAdmin.sim.monster") == "2|6123|Green Worm");
    mgr.filter_chat("CHAT_MSG_SAY", "· 31 × Reinforcement Potion (TID 486)", "");
    mgr.filter_chat("CHAT_MSG_SAY", "· 8 × Small Life Potion (TID 190)", "");
    frame_ui(&mgr);
    check("objets simulés lus", eval(&mgr, "(function() local t = {} for _, i in ipairs(ArchCoreAdmin.sim.items) do t[#t + 1] = i.count .. 'x' .. i.tid end return table.concat(t, ',') end)()") == "31x486,8x190");
    let line = eval(&mgr, &format!("{loot}.results.rows[1].text:GetText() .. '|' .. {loot}.results.rows[1].cols[1]:GetText() .. '|' .. {loot}.results.rows[1].cols[2]:GetText()"));
    check(&format!("lignes de la liste ({line})"), line == "Reinforcement Potion|31|6.2");
    check("icône d'un objet simulé", eval(&mgr, &format!("tostring({loot}.results.rows[2].icon.tex:GetTexture())")).to_lowercase().contains("l0000040"));
    check("résumé", eval(&mgr, &format!("{loot}.summary:GetText()")).contains("6123"));
    check("monstre simulé retenu, avec son niveau", eval(&mgr, "ArchCoreAdmin.db.global.monsters[450].name .. ArchCoreAdmin.db.global.monsters[450].level") == "Green Worm1");
    check("ligne « · » après la fin de la liste ignorée", mgr.filter_chat("CHAT_MSG_SAY", "· 1 × Passport (TID 198)", "").is_some() && eval(&mgr, "#ArchCoreAdmin.sim.items") == "2");
    let o = eval(&mgr, overlap_lua);
    check(&format!("mise en page du butin : {o}"), o.is_empty());
    eval(&mgr, &format!("local p = {loot} p.drop:SetText('') p.gold:SetText('3') ArchCoreAdmin.rates.drop = 1.5 return ''"));
    slashes(&mgr);
    click_at(&mgr, sim);
    let sent = slashes(&mgr);
    check(&format!("taux d'or seul : taux de butin du serveur ajouté {sent:?}"), sent == vec!["/simloot 450 500 1.5 3.0".to_string()]);

    // 11. Réduire la fenêtre au lieu de la fermer, puis la rétablir.
    click_at(&mgr, "ArchCoreAdmin.minimizeButton");
    frame_ui(&mgr);
    let state = eval(&mgr, "tostring(ArchCoreAdminFrame:IsShown()) .. math.floor(ArchCoreAdminFrame:GetHeight()) .. tostring(ArchCoreAdmin.sections[1].tab:IsShown()) .. tostring(ArchCoreAdmin.logo:IsShown())");
    check(&format!("fenêtre réduite ({state})"), state == "true32falsefalse");
    check("titre de la barre réduite", eval(&mgr, "ArchCoreAdmin.miniTitle:GetText()").contains("ArchCore Admin"));
    check("champs gardés", eval(&mgr, &format!("{loot}.tid:GetText()")) == "450");
    click_at(&mgr, "ArchCoreAdmin.minimizeButton");
    frame_ui(&mgr);
    check("fenêtre rétablie sur le même onglet", eval(&mgr, &format!("math.floor(ArchCoreAdminFrame:GetHeight()) .. tostring({loot}:IsShown())")) == "492true");
    eval(&mgr, "ArchCoreAdmin:SetMinimized(true) return ''");
    eval(&mgr, "ArchCoreAdmin:Toggle() return ''");
    check("le lanceur rétablit la fenêtre réduite", eval(&mgr, "tostring(ArchCoreAdminFrame:IsShown()) .. tostring(ArchCoreAdmin.minimized)") == "truenil");
    check(&format!("pas d'erreur Lua (objets, butin, réduction) {:?}", mgr.errors()), mgr.errors().is_empty());

    // 12. Compte sans droits : tout est grisé.
    eval(&mgr, "ArchCoreAdmin:ProbeLevel() return ''");
    slashes(&mgr);
    mgr.filter_chat("CHAT_MSG_SAY", "Commande inconnue : /SetExp", "");
    check("niveau 0", eval(&mgr, "ArchCoreAdmin.gmLevel") == "0");
    check("boutons grisés", eval(&mgr, "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b:IsEnabled() then return b.command end end return 'aucun' end)()") == "aucun");
    check(&format!("pas d'erreur Lua {:?}", mgr.errors()), mgr.errors().is_empty());

    mgr.save_all().unwrap();
    let saved = std::fs::read_to_string(sv.join("ArchCoreAdmin.lua")).unwrap_or_default();
    check("SavedVariables écrites", saved.contains("Anchorville") && saved.contains("Potion de vie") && saved.contains("Loup gris"));
    println!("--- {} octets de SavedVariables", saved.len());

    // 13. Client sans catalogue d'objets : repli sur la saisie du TID et les favoris.
    let sv2 = root.join("sv/sans-catalogue");
    let mut mgr = AddonManager::new(&sv2).unwrap();
    mgr.set_host(|h| {
        h.player = Some(me.clone());
        h.screen = (1280.0, 720.0);
    });
    mgr.load_dir(&root.join("../..")).unwrap();
    mgr.sync_world(Some(me.clone()), vec![], Some(vec![]));
    mgr.fire_event("PLAYER_LOGIN", &[]);
    mgr.fire("PLAYER_ENTERING_WORLD", (true, false));
    mgr.run_slash("/aca items");
    frame_ui(&mgr);
    check("sans catalogue : détecté", eval(&mgr, "tostring(ArchCoreAdmin:HasItemCatalog())") == "false");
    check("sans catalogue : recherche masquée, favoris listés", eval(&mgr, "tostring(ArchCoreAdmin.sectionsByKey.items.page.search:IsShown()) .. tostring(ArchCoreAdmin.sectionsByKey.items.page.categories.armor:IsShown())") == "falsefalse");
    eval(&mgr, "ArchCoreAdmin.sectionsByKey.items.page.tid:SetText('190') return ''");
    slashes(&mgr);
    eval(&mgr, "ArchCoreAdmin:Run('additem', { ArchCoreAdmin.sectionsByKey.items.page.tid:GetText(), 2 }) return ''");
    check("sans catalogue : /additem par TID", slashes(&mgr) == vec!["/additem 190 2".to_string()]);
    let o = eval(&mgr, overlap_lua);
    check(&format!("sans catalogue : mise en page {o}"), o.is_empty());
    check(&format!("sans catalogue : pas d'erreur Lua {:?}", mgr.errors()), mgr.errors().is_empty());

    // 14. Sonde du niveau MJ quand les réponses en « / » n'arrivent pas (ArchRust actuel).
    let sv3 = root.join("sv/sonde");
    let mut mgr = AddonManager::new(&sv3).unwrap();
    mgr.set_host(|h| {
        h.player = Some(me.clone());
        h.screen = (1280.0, 720.0);
    });
    mgr.load_dir(&root.join("../..")).unwrap();
    mgr.sync_world(Some(me.clone()), vec![], Some(vec![]));
    mgr.fire_event("PLAYER_LOGIN", &[]);
    mgr.fire("PLAYER_ENTERING_WORLD", (true, false));
    check("sonde : /SetExp", slashes(&mgr) == vec!["/SetExp".to_string()]);
    mgr.update(6.0);
    check("sonde : silence, /GetExp", slashes(&mgr) == vec!["/GetExp".to_string()]);
    check("sonde : réponse de /GetExp masquée", mgr.filter_chat("CHAT_MSG_SAY", "Taux d'expérience : 1.0", "").is_none());
    check("sonde : niveau 3 ou plus déduit", eval(&mgr, "ArchCoreAdmin:LevelText()").contains("3 ou plus"));
    eval(&mgr, "ArchCoreAdmin:ProbeLevel() return ''");
    slashes(&mgr);
    mgr.update(6.0);
    slashes(&mgr);
    mgr.update(6.0);
    check("sonde : compte sans droits, rien de plus envoyé", slashes(&mgr).is_empty());
    check("sonde : niveau resté inconnu", eval(&mgr, "tostring(ArchCoreAdmin.gmLevel)") == "nil" && eval(&mgr, "tostring(ArchCoreAdmin.probing)") == "nil");
    check(&format!("sonde : pas d'erreur Lua {:?}", mgr.errors()), mgr.errors().is_empty());

    // 15. Client qui lit les tables du serveur (API décrite dans docs/BESOINS-CLIENT-SERVEUR.md, simulée
    // ici en Lua : archrust-addons ne l'a pas encore). Points 05, 06, 11 et 14 au complet.
    let sv4 = root.join("sv/tables-serveur");
    let mut mgr = AddonManager::new(&sv4).unwrap();
    let mut items = catalog();
    items.push(ItemTemplateInfo { tid: 15151, name: "Divine Blight Shield".into(), kind: 4, part: 10, level: 80, stack: 1, ..Default::default() });
    mgr.set_host(|h| {
        h.player = Some(me.clone());
        h.screen = (1280.0, 720.0);
        h.item_templates = Arc::new(items);
    });
    mgr.load_dir(&root.join("../..")).unwrap();
    mgr.run_script(
        r#"
        local base = ArchRust.GetItemTemplate
        local extra = {
          [1] = { classes = { 2 }, races = { 1, 2 }, minSocket = 1, maxSocket = 4, stats = { Physical_Min_Damage = 7, Physical_Max_Damage = 9, ["ATK Speed"] = 75, Fire_Min_Damage = 2, Fire_Max_Damage = 3 } },
          [530] = { classes = { 1 }, races = { 1 }, minSocket = 2, maxSocket = 2, stats = { Physical_Defense_Point = 15, STR_Bonus_Point = 3, Water_Defense_Rate = 5, DUR = 40 } },
          [531] = { classes = { 1 }, races = { 2 } },
          [660] = { classes = { 1 }, races = { 2 } },
          [900] = {},
        }
        function ArchRust.GetItemTemplate(tid)
          local t = base(tid)
          if not t then return nil end
          t.server = t.tid ~= 15151
          local e = extra[t.tid] or {}
          t.classes, t.races = e.classes or {}, e.races or {}
          t.minSocket, t.maxSocket, t.stats = e.minSocket, e.maxSocket, e.stats
          return t
        end
        function ArchRust.GetMonsterTemplates()
          return { { tid = 450, name = "Green Worm", level = 1 }, { tid = 451, name = "Grey Wolf", level = 7 }, { tid = 452, name = "Grey Bear", level = 12 } }
        end
        "#,
    )
    .unwrap();
    mgr.sync_world(Some(me.clone()), vec![unit(0x5000_0001, "Ver vert", -474000.0, -65000.0)], Some(vec![]));
    mgr.fire_event("PLAYER_LOGIN", &[]);
    mgr.fire("PLAYER_ENTERING_WORLD", (true, false));
    mgr.run_slash("/aca items");
    frame_ui(&mgr);
    let rows = |mgr: &AddonManager| eval(mgr, &format!("(function() local t = {{}} for _, it in ipairs({page}.list.items) do t[#t + 1] = it.tid end return table.concat(t, ',') end)()"));
    check(&format!("tables du serveur : l'objet absent n'est pas proposé ({})", rows(&mgr)), rows(&mgr) == "190,198,486,1,900,530,531,532");
    check("tables du serveur : note", eval(&mgr, &format!("{page}.note:GetText()")).contains("8 objets dans les tables du serveur"));
    check("tables du serveur : filtre de classe affiché", eval(&mgr, &format!("tostring({page}.classButton:IsShown())")) == "true");
    let o = eval(&mgr, overlap_lua);
    check(&format!("tables du serveur : mise en page {o}"), o.is_empty());
    click_at(&mgr, &format!("{page}.classButton"));
    frame_ui(&mgr);
    check(&format!("classe Knight ({})", rows(&mgr)), eval(&mgr, &format!("{page}.classButton:GetText()")) == "Classe : Knight" && rows(&mgr) == "900,530");
    click_at(&mgr, &format!("{page}.classButton"));
    frame_ui(&mgr);
    check(&format!("classe Archer ({})", rows(&mgr)), rows(&mgr) == "1,900");
    eval(&mgr, &format!("local b = {page}.classButton b:GetScript('OnMouseWheel')(b, 1) b:GetScript('OnMouseWheel')(b, 1) return ''"));
    frame_ui(&mgr);
    check("molette : retour à toutes les classes", eval(&mgr, &format!("{page}.classButton:GetText()")) == "Classe : Toutes");
    eval(&mgr, &format!("{page}.search:SetText('shield') return ''"));
    frame_ui(&mgr);
    eval(&mgr, &format!("local r = {page}.list.rows[1] r:GetScript('OnEnter')(r) return ''"));
    let tip = tooltip_text(&mgr);
    check(&format!("info-bulle complète : {tip}"), tip.contains("Classes : Knight") && tip.contains("Emplacements : 2") && tip.contains("Défense physique : 15") && tip.contains("Force : 3") && tip.contains("Résistance : eau : 5") && tip.contains("Durabilité : 40"));
    eval(&mgr, &format!("local r = {page}.list.rows[1] r:GetScript('OnLeave')(r) {page}.search:SetText('') return ''"));
    frame_ui(&mgr);
    eval(&mgr, &format!("local r = {page}.list.rows[4] r:GetScript('OnEnter')(r) return ''"));
    let tip = tooltip_text(&mgr);
    check(&format!("info-bulle d'une arme : {tip}"), tip.contains("Classes : Archer, Hunter") && tip.contains("Emplacements : 1 à 4") && tip.contains("Dégâts physiques : 7 - 9") && tip.contains("Dégâts : feu : 2 - 3") && tip.contains("Vitesse d'attaque : 75"));
    eval(&mgr, &format!("local r = {page}.list.rows[4] r:GetScript('OnLeave')(r) {page}.tid:SetText('15151') return ''"));
    frame_ui(&mgr);
    check("aperçu d'un objet absent du serveur", eval(&mgr, &format!("{page}.previewInfo:GetText()")).contains("absent du serveur"));
    slashes(&mgr);
    let additem = "(function() for _, b in ipairs(ArchCoreAdmin.widgets) do if b.command == 'additem' then return b end end end)()";
    click_at(&mgr, additem);
    mgr.update(6.0);
    let s = eval(&mgr, &format!("{page}.status:GetText()"));
    check(&format!("silence sur un objet absent : cause sûre ({s})"), s.contains("Divine Blight Shield (TID 15151)") && s.contains("n'a pas cet objet"));
    mgr.run_slash("/aca loot");
    frame_ui(&mgr);
    let monsters = |mgr: &AddonManager| eval(mgr, &format!("(function() local t = {{}} for _, m in ipairs({loot}.monsters.items) do t[#t + 1] = m.tid .. (m.level and (':' .. m.level) or '') end return table.concat(t, ',') end)()"));
    check(&format!("liste complète des monstres, en vue d'abord ({})", monsters(&mgr)), monsters(&mgr) == "96,450:1,452:12,451:7");
    eval(&mgr, &format!("{loot}.monsterSearch:SetText('grey') return ''"));
    frame_ui(&mgr);
    check(&format!("recherche dans la liste complète ({})", monsters(&mgr)), monsters(&mgr) == "452:12,451:7");
    let o = eval(&mgr, overlap_lua);
    check(&format!("tables du serveur : mise en page des monstres {o}"), o.is_empty());
    check(&format!("tables du serveur : pas d'erreur Lua {:?}", mgr.errors()), mgr.errors().is_empty());
}
