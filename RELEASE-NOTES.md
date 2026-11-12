# Release notes in Czech

Sara's release notes in Czech, read by the welcome window's News pane while
Czech is the language in force. A machine draft, line for line with the English
`CHANGELOG.md` of Sara's repository: each section has as many lines as the
English one, and a section that has not shows in English. Every section carries
the mark `machine draft, not reviewed` until a reviewer has read it.

## 1.0.0-alpha.1

<!-- machine draft, not reviewed -->
Dokument může být ekvirektangulární panorama, zobrazené jako obloha kolem vás a malované v tomto pohledu. Tahy a filtry přecházejí přes šev celé a soubory `.hdr` se otevírají a převádějí.
Panel Graf ukazuje Fourierův spektrogram obrázku a jeho radiální průměr.
Nový panel Statistiky čte skupiny hodnot, dominantní odstíny, pokrytí, hustotu hran, profil sytosti, tahy za minutu a střední tlak a čas strávený s každým nástrojem a každou vrstvou. Každý řádek lze vypnout zvlášť.
Každá vrstva malby může spustit simulaci (Rozptyl, Život nebo Gray-Scott) a filtr se může přehrát v čase do očíslovaných snímků.
Nové filtry: Posterizace, Vinětace, Laplaceova mapa, Záře, Chromatická vada, Korekce objektivu, Horké pixely, Zrno, Dolní propust, Horní propust, Odstranění červených očí, Bílý bod, vyhledávací tabulka `.cube` a vrstva tónovacího mapování. Panel Filtry je prochází a uchovává uložené podoby.
Vrstva může nést živou transformaci, kterou řídí nástroje Transformace a Ořez a zapisuje Zapéct transformaci.
Zrcadlová vrstva čte pouze malbu svého zdroje a její osa se přetahuje na plátně.
Obraz > Barevný prostor a Soubor > Nový sdílejí jeden výběr barevného prostoru, který přijímá soubor profilu ICC a uchovává prostory, které uložíte.
Rozvržení panelů mohou obsahovat vaše vlastní prvky: složený panel se vytváří v části Rozvržení a panely, plní se na stránce Prvky a Obnovit dodané vrací jeho úpravy.
Načíst špičku čte roury GIMPu a špičky `.abr` a štětce mohou použít přechod jako zdroj barvy.
Magnetické laso se připojilo k Lasu v panelu nástrojů a vrstva Obarvit pomáhá obarvit kresbu linkami.
Vektorové vrstvy kreslí obdélníky a elipsy s výplní a tahem v barvě s plovoucí desetinnou čárkou nástrojem Tvar a nástroj Objekt je přesouvá a mění jejich velikost.
Sara má český překlad, strojový návrh označený jako dosud nerevidovaný.
Soubor uložený před tímto vydáním může na několika úrovních exportovat trochu jinak tam, kde vrstva efektu rozmazává to, co vytvořilo její vlastní zrcadlo, protože rozostření nyní čte zrcadleného souseda přes okraj bloku místo nezrcadleného, a šev, který tam kreslila starší verze, je pryč.

## 0.19.1

<!-- machine draft, not reviewed -->
Filtr › Mapa přechodu položí barevnou škálu přes světlost vrstvy, použitou jednou nebo připojenou tak, aby sledovala malbu.
Zrušení skupiny s filtrem zachová obraz, jaký byl, každý jeho texel.
Tah pravým tlačítkem, dalším tlačítkem nebo tlačítkem na těle pera se už nad panelem nezastaví.
Rozvržení panelů, které jste změnili, se po živé změně měřítka rozhraní znovu vejde do okna.
Dialog Přizpůsobení importu jmenuje gamut, o kterém PNG nebo TIFF říká, že ho obsahuje.
Modul může zaregistrovat pole štětce, které spouští vlastní jádro, a dodat vlastní jádro generátoru pro generovanou vrstvu.

## 0.19.0

<!-- machine draft, not reviewed -->
Uvítací okno se otevírá obrazem namalovaným v Saře, „Nad hřebeny“, přes celou svou horní část.
Světlo obrazu sleduje hodinu, kdy se okno otevře: svítání, den, soumrak a noc, každé přechází v další.
Uvítací obraz může mít roční období, vybraná podle měsíce a země vašeho národního prostředí, včetně jižní polokoule. Dodávaný obraz má zatím jedno období.
Dokument se otevře na vrstvě, která byla aktivní při uložení.
Na Linuxu Sara čte tlačítka pera z jádra, takže je slyšet i uvolnění horního tlačítka ve vzduchu a další tah maluje. `packaging/install.sh` nabízí pravidlo, které jí je dovolí číst, a sám nikdy nespouští `sudo`.

## 0.18.0

<!-- machine draft, not reviewed -->
Šumový štětec maluje jeden plynulý tah bez otisků. Jeho textura běží podél tahu, přítlak rozhoduje, kolik z ní je vidět, a hrot poté tvaruje okraj.
Náhodnost šumového štětce se podél tahu mění. Zatáčka si ponechá díry, které má rovný tah, a lehký tah si je ponechá i pod perem, které se chvěje nebo spočívá.
Řádek Hrot šumového štětce načte obrázkový hrot, vybraný z mřížky obrázků, kterou lze filtrovat podle složky a která se po zaplnění posouvá.
První šumový tah po výběru šumového přednastavení už nezaostává.
Výšky impasta stoupají i klesají a sčítají se. Tah posouvá povrch k vlastní výšce a tlačí před sebou starou výšku i starou barvu své vrstvy.
Barva se na okrajích tahu hromadí jen pod silným přítlakem.
Vrstva › Rastrovat impasto zapéká reliéf vrstvy do jejích pixelů.
Filtr štítků přednastavení štětců jmenuje každý štítek zvlášť a vybraný štítek zůstane vybraný.
Stisk kolečka myši ve výchozím stavu posouvá, s vlastní vazbou.
Druhý dotek s dále drženým horním tlačítkem pera znovu maže.
Otevřená nabídka ustoupí titulku nabídky, na který se ukazatel přesune. Stisk, který zavírá nabídku nebo uvítací okno, nemaluje.
Pravý stisk nebo Escape během tažení posuvníku vrátí hodnotu zpět.
Moduly › Místní server je přepínač a jeho dialog zkopíruje výzvu pro agenta. Jeho otevření nechá ukazatel tam, kde je, a stisk mimo dialog ho zavře.

## 0.17.4

<!-- machine draft, not reviewed -->
Uložit jako v editoru štětců ponechá přednastavení, ze kterého jste vyšli, a načte kopii.
Transformace převrácená v zrcadleném režimu zachová barvu vrstvy a její rámeček obepne barvu tak, že je každý úchyt na dosah.
Osy zrcadlení stojí na dvou úchytech, které můžete umístit kamkoli.
Výplň zahájená na tmavé barvě nechá prázdné pixely být a uzavře malé mezery.
Každá změna výběru je krok zpět. Shift+Alt dělá průnik, Zvětšit a Zmenšit jsou v nabídce Výběr a tažení uvnitř výběru posune jeho obrys.
Eliptický výběr nabízí vyhlazování a kouzelná hůlka má přepínač Souvislé.
Rozsah barev vybírá kliknutím na plátno, ukazuje náhled a při výchozí neurčitosti se vyhne neutrálnímu podkladu.
Převrátit a Otočit fungují na obraz, vrstvu i výběr. Nabídka Úpravy vyplní a vymaže výběr.
Vložit vezme obraz ze schránky plochy a Kopírovat ho tam vloží.
Export do EXR obsahuje lineární sRGB, export do JPG sloučí průhlednost na jednu barvu a Export bere formát z přípony názvu.
Sara otevírá TIFF. Uložit jako přidá .sad a varuje, když název končí příponou obrázku.
Kapátko nad prázdným pixelem nechá barvu, jaká byla.
Sloučit a Sloučit dolů fungují nad vrstvou podkladu nebo filtru na dně a Sloučit dolů sloučí každou vybranou vrstvu.
Smazání několika vrstev je jeden krok zpět, stejně jako přejmenování jedné, které nyní otevře malý dialog.
Posun vrstvy nahoru nebo dolů drží potomky skupiny pohromadě. Izolovat skupinu říká, co dělá.
Připojený filtr se drží výběru, úpravy jeho posuvníků jsou kroky zpět a jeho panel odejde, když je aktivní jiná vrstva.
Připojené filtry vrstvy jsou vypsány v pořadí, v jakém čtete zásobník, a vrstva úprav je jeden řádek pojmenovaný podle svého filtru.
Práh dává dva čisté tóny na měkkých okrajích. Jas a Kontrast pokrývají celé své posuvníky a Posun s přetečením je vystředěn na nulu.
Úrovně a Křivky dávají čitelný histogram s kapátky. Invertovat, Odbarvit a Pixelizovat jsou v nabídce Filtr.
Každý filtr se vysvětluje sám a filtr, který nemůže běžet na aktivní vrstvě, řekne proč.
Žádný filtr nezapíše do plátna ani do barvy poškozený pixel.
Normálová mapa ukazuje na plátně svou zakódovanou barvu.
Softproof nabízí cíl a ukazuje svůj účinek.
Vyhledání barvy se otevře s nápovědou, ukazuje jen barvy palety a pixel mezi dvěma barvami smíchá, místo aby skočil.
Vzorky barev nesou jména a odebrání jednoho lze vrátit. Hexadecimální pole potvrdí hodnotu, když ztratí klávesnici.
Tvar výběru barvy se volí v panelu a alfa popředí se zobrazí nebo zahodí.
Výchozí štětec položí vybranou barvu jedním tahem. Tečkovaná čára a Plátěné scumblování kreslí, co říkají jejich názvy.
Shift+klik nakreslí rovnou čáru od posledního tahu.
Přechod sleduje vaše dvě barvy, dokud neupravíte jeho škálu, ponechá si úchyty po uvolnění a dodávají se hotové škály.
Každý kreslený hrot maluje vlastní obrázek a štětcová trubka se načte před stiskem.
Guma vyskakovací palety pak vrátí režim prolnutí.
Zkratku lze vymazat a Zpět na výchozí Sary vrátí každý akord.
Nástroj Lupa přiblíží kliknutím a oddálí Shift+klikem. Přiblížení se čte jako velikost obrazu na obrazovce a Ctrl+0 dělá, co nastavíte.
Převrátit pohled svisle už nevázne a obrázky přednastavení se opět rychle plní.
Úchyt panelu drží svou horní hranu a plovoucí panel se zastaví na okraji okna.
Režim soustředění ponechaný zapnutý při zavření vrátí panely při dalším spuštění.
Vrstva Papír se jmenuje Papír, ukazuje svůj papír a jde pod barvu.
Horní tlačítko na těle pera se rozezná od hrotu, i když fokus drží Předvolby.
Záznamník počítá snímky tak, jak jsou pořízeny, a řekne, kdy je video hotové.
`sara --version` vypíše verzi a skončí.
V zápisníku buňka nad prázdnou vrstvou běží přes celé plátno, duplikovaná vrstva dostane požadované jméno a změna se ukáže, když se okno Sary vrátí. Zápisník bez spuštěné Sary ji spustí.

## 0.17.3

<!-- machine draft, not reviewed -->
Sara dodává autorovy vlastní kreslené hroty štětců, štětec na každém z 23, jako balíček „Sara drawn“.
Velikost podle přítlaku sleduje pero téměř úměrně.
Tab skryje panely, ať bylo naposledy stisknuto cokoli, a se skrytými panely je změna barvy, velikosti nebo přednastavení jedno gesto.
Přizpůsobit umístí malbu mezi sloupce panelů a malba se při výchozím přiblížení ukáže blíž.
Posuvník velikosti přijme napsané číslo a jemný krok a říká, že jde o poloměr. Backspace nad posuvníkem štětce vrátí hodnotu přednastavení.
Výběr barvy dává svému kruhu šířku a čte ve stupních, procentech a od 0 do 255. Stisk na vzorníku vybere, co kruh upravuje, a dvojice má prohození.
Každý ovládací prvek, který stisknete, nese popisek.
Ctrl+Shift+A zruší výběr a Zamknout alfu řekne, když se zapne.
Výběr lasem je ve výchozím stavu vyhlazený a výběr, který se uzavře bez plochy, to řekne. Eliptický výběr má v nástrojích vlastní tlačítko.
Stisk kdekoli na dlaždici přednastavení ho vybere a dá vám štětec do ruky. Každá dlaždice ukazuje vlastní tah a lomítko přepne na předchozí přednastavení.
Panel Vrstvy pojme při výchozí výšce čtrnáct řádků, s Duplikovat, Skupina, Sloučit a Maska v řádku akcí. Náhled ukazuje tmavou barvu na šachovnici, přepínače a zámky řádku čtou zapnuto a vypnuto a klávesa posouvá aktivní vrstvu nahoru a dolů.
Tah, jehož kotouč pokrývá plátno, maluje až k okraji, a tah, který nic nenamaluje, řekne proč.
Shift a tažení mění velikost štětce a Shift+mezerník nebo tažení perem otáčí pohled.
Symetrie a Převrátit pohled jsou dvě slova pro dvě práce.
Druhý řádek horní lišty je zapnutý a drží každou volbu nástroje ve skupinách Štětec, Tah a Pohled. Volba, která se nevejde, se přesune do přetečení.
Stavový řádek ukazuje přiblížení, velikost a barevný prostor a nabídka Zobrazení ho skryje.
Nový dokument jmenuje výchozí barevný prostor, nabízí velikosti, vybírá pozadí a podklad a otevírá se ze šablony nebo ji ukládá. Obrázek se otevře v 16bitové plovoucí čárce, pokud jste nezvolili jinak.
Předvolby seskupují stránky podle toho, co děláte. Jejich hledání najde řádky podle slov malíře i podle klávesy, každé dveře k nim vedou na jejich řádek, každé číslo nese jednotku a Obnovit vše se nejdřív zeptá.
Třináct stránek panelů je jedna stránka Rozvržení a panely a každé dodávané rozvržení vejde do svých sloupců při jakémkoli měřítku rozhraní.
Každý dialog se otevře uvnitř okna při každé velikosti a měřítku, s tlačítky v jednom řádku a jednom pořadí, Zrušit první. Escape zruší dialog, jakmile klávesnici nedrží žádné textové pole.
Druhý dialog se otevře vpravo dole od prvního a Přejmenovat vrstvu a uvítací okno se otevřou uprostřed hlavního okna.
Profil Krita ukládá a vzorkuje ve dvou krocích a drží sloty štětců na Ctrl+Alt a číslicích a Import z Krity čte každý název klávesy, který Krita zapisuje.
Práce Krity, které Saře chyběly, mají příkazy, každý příkaz nabídky má řádek na stránce zkratek a stránka najde příkaz podle jeho klávesy.
F1 otevře příručku.
Snímková frekvence ve výchozím stavu sleduje displej a první snímky studeného startu už neváznou.
Panel Reference se otevírá zavřený a dává obrázku prostor, panel Informace začíná dokumentem a záznamník ukazuje, kam zapisuje.
Vrstvy úprav a efektů se ptají, co obsahují.
Papírový a tkaný podklad za dokumentem se mění s přiblížením a papírový podklad má své měřítko a ostatní nastavení.
Guma impasta při mazání zplošťuje výšku.
Nástroj Záplata plní z vlastní textury obrazu.
Velikost vzorku kapátka je posuvník na liště.
Hladit ve Zkapalnění vyrovná jakékoli pixely a nad prázdným plátnem nevytvoří nic ani žádný krok zpět. Krok zpět během sezení zkapalnění sezení nejdřív zavře.
Souborový dialog se otevře ve složce, kde byl naposledy opuštěn.
Autorovo růžové téma se dodává jako vestavěná paleta a uvítací okno má kartu Tipy.
Sara píše každé zobrazené slovo jedním způsobem a každý popisek nastavení říká, co dostanete.
Čistá primární barva uložená v 16bitové plovoucí čárce se zobrazí sama sebou.
Na Windows uvolněný panel tažený perem pod oběma ovladači sleduje pero a start neukáže žádné okno, dokud není jeho obraz celý.
GIMP otevře průchozí skupinu tak, jak ji kreslí Sara, nebo export řekne, že ne.
V zápisníku se sara.init() připojí, otevře dokument sRGB a přečte celé plátno. Posuvník se deklaruje pomocí hint_range a jádro spustí okamžitě znovu, posuvník NumPy zapisuje 30 snímků za sekundu, buňka může číst druhou vrstvu nebo importovat obrázek jako vrstvu a zápisník se znovu připojí, když ho dveře odpojí.

## 0.17.2

<!-- machine draft, not reviewed -->
Vypnutí přetečení horní lišty už Saru nezasekne ani neshodí.
Šumový štětec je jedním z enginů nástroje Štětec, nikoli samostatným nástrojem.
Reliéf impasta se ve výchozím stavu kreslí o polovinu méně strmý. Síla, kterou jste si zvolili sami, zůstane.
Textové pole si drží vlastní klávesy pro úpravy, takže Ctrl+A v poli Hex vybere text, a ne obraz.
Enter stiskne tlačítko, na kterém je obrys.
Stisk těsně po Tabu, tam kde chvíli předtím stál panel, už nemaluje na obraz.
Výplň bez výběru řekne, že vyplnila celou vrstvu.
Přemapování klávesy na už obsazenou se nejdřív zeptá a nenechá žádnou klávesu mrtvou a Začít znovu obnoví dodávanou mapu kláves.
Dva filtry stejného druhu připojené k vrstvě jsou od sebe očíslovány.
Kapátko umí vzít to, co ukazuje pohled se zapnutými filtry.
Přepínače tlačítek Maximalizovat a Skrýt se nastavují jednou pro všechny panely.
Název skupiny v panelu Vrstvy si při posouvání seznamu drží výpustku a každý název, který Sara zkrátí, končí výpustkou.
Okno O aplikaci se vejde na obrazovku vysokou 1024 pixelů a jeho adresa otevře repozitář.
Graf FPS říká, že Sara odpočívá, místo aby padal k nule.
Uvítací okno stojí nad rozostřením, zatímco se Sara spouští.
Znovu načíst moduly čte váš vlastní modul stejně jako start.
Na Windows tlačítka na těle pera vybírají kapátkem a mažou, kroužek drží krok s ukazatelem a sleduje pero na panel pod Windows Ink, malý štětec drží krok s perem, žádný snímek startu nedrží okno, výběr souboru se otevře hned i s namapovanou síťovou jednotkou, oznámení v rohu stojí nad uvolněnými panely, přivolaný panel nenechá žádného ducha, zamrznutí zanechá řádek v logu a skript v Pythonu umí číst vrstvu a ukázat obrázek.
Poznámka pořízená s vypnutými podokny zaznamená řádek pod perem.

## 0.17.1

<!-- machine draft, not reviewed -->
Každé přednastavení štětce nese hvězdičku ke kliknutí, v panelu Knihovna štětců i v editoru štětců, a přepínač S hvězdičkou nad přednastaveními vypíše jen ta označená, spolu se štítkem a hledáním. Hvězdičky se drží ve vašem profilu a nikdy necestují ve sdíleném balíčku.
Stabilizovaný tah končí tam, kde se pero zvedlo, i po rychlém pohybu.
Sloučení filtru umístěného za Ditherem zapeče jen ten filtr a Dither nechá připojené, stále poslední.
Náhledy Ditheru v dialogu Filtr a v prohlížeči filtrů už neopakují vzor každých 256 pixelů, takže odpovídají tomu, co zapíše Použít.
Připojený filtr Úrovně a vrstva úprav Úrovně kreslí graf obrazu, který čte Vyrovnání, místo aktivní vrstvy.
Řádek FPS v panelu Informace ukazuje číslo i v klidu, kde dřív stálo „odpočívá“.

## 0.17.0

<!-- machine draft, not reviewed -->
Filtr se nyní může stát vrstvou úprav, která mění vše pod sebou a nechává svá nastavení upravitelná. Spouští bodové filtry a rozostření a sloučení nebo sloučení dolů ji zapeče. Dialog Filtr nabízí Zapéct, Připojit nebo Vrstva a Zapéct zůstává výchozí.
Úrovně mají tlačítko Vyrovnání, které vyplní mapu z histogramu vrstvy, v dialogu, na připojeném filtru Úrovně i na vrstvě úprav Úrovně.
Nástroj Zkapalnění tlačí, hladí, víří, zmenšuje a zvětšuje barvu.
Kruh odstínů nese šedé značky u červené, zelené, modré, azurové, purpurové a žluté a přepínač Zachovat sytost na stránce Výběr barvy drží vzdálenost barvy od šedé, když se mění její odstín.
Panel Reference umí ukázat jeden obrázek samotný.
Transformace má zrcadlený režim, ve kterém tažení rohu posune i protější roh.
Mapování gamutu v pohledu najde okraj gamutu přesně, místo aby ho hledalo.
Panel Informace kreslí průběžný graf FPS.
Vlastní filtry skupiny na vrstvě s dvojnásobným rozlišením běží v detailu té vrstvy.
Nové filtry: Dither (Bayer, prokládaný gradientní šum nebo modrý šum), který vždy běží poslední, a Vlnění, které čeří vrstvu podle šumového pole.
Vrstva efektu spouští své filtry nad jinou vrstvou nebo skupinou, kterou jmenuje, a vrstva scény ukazuje živý viewport Godotu jako pozadí plátna.
Šumový štětec umí rozmazávat stejně jako razítkový štětec.
Napsání čísla nad plátnem nastaví krytí štětce.
Tlačítko skrytí panelů je ve výchozím stavu zapnuté. Malíř, který ho vypnul, ho má dál vypnuté.
Otevřený seznam vedle nabídky už pod sebou nemá nakreslený kroužek štětce.
Nový profil začíná malovat dodávaným přednastavením a jeho deset slotů štětců je předem naplněno.
Každá velikost textu sleduje písmo tématu a každá věc má jedno jméno, ať se objeví kdekoli.
Příkazy nabídek a tlačítka, která by nic neudělala, jsou zakázána a Vítejte se otevře bez ničeho prázdného či ztlumeného.
Kliknutí na titulkový pruh panelu už nemění uložené rozvržení.
Předvolby se vejdou do svého panelu a každou stránku otevírají nahoře a jejich řádky říkají, co dělají. Nastavení souborů mají vlastní stránku Soubory a stránka Barevné prostory jmenuje výchozí prostor a posouvá se.
Nabídky ukazují své zkratky tak, jak je píše stránka Klávesové zkratky.
Pro agenta dveře na požádání vypíšou své kroky, každá verze nese průvodce pro agenty a Nápověda › Připojit agenta nebo `--agent-help` dá první zprávu k odeslání.

## 0.16.3

<!-- machine draft, not reviewed -->
Kruhy odstínů HSV a OKHSV kladou každou barvu pod stejný úhel, žlutou dolů.
Celá obrazovka je jen na F11. Zkratka, kterou jste si přiřadili sami, zůstane, jak byla.
Mapování gamutu je vlastní přepínač pohledu vedle Tónově mapovat světla, ve výchozím stavu zapnutý, takže barva stlačená pod nulu se na obrazovce mapuje i s vypnutým tónovým mapováním.
Kanál Světlost histogramu Úrovní počítá světlost Oklab.
Kruh nástroje Záplata sleduje klávesy hranatých závorek a tažení se Shiftem stejně jako štětec.
Zachovat prolnutí je přepínací tlačítko jako přepínač Stabilizátoru a otočení napsané mimo -180 až 180 se zalomí, místo aby se zastavilo na konci.
Vrstva přetažená nad nebo pod seznam přistane na tom jeho konci.
Vysvětlivky dialogu přizpůsobení jsou o velikost menší a přednastavení štětců se načtou po prvním snímku, takže se Sara otevře dřív.
Živý tah na maskované, oříznuté nebo filtrované vrstvě s dvojnásobným rozlišením dokumentu ukazuje svůj detail a první otisk razítkového přednastavení čte svůj papír i bez najetí před stiskem.
Tah mimo plátno neukládá nic za jeho okrajem.

## 0.16.2

<!-- machine draft, not reviewed -->
Úklidové vydání, takže malíř by neměl vidět žádnou změnu. Pod povrchem každý soubor deklaruje své typy, komentáře byly znovu pročištěny a kontroly je nyní hlídají a každý test sedí vedle funkce, kterou testuje.
Změna tématu už Saru nezasekne a pět skriptovaných sezení, která se dřív zasekávala, nyní doběhne.
Pro studenta nebo agenta mluví dveře Sary prostým HTTP, takže samotný `curl` umí Saru spustit, malovat a zapsat obrázek. Druhy kroků jsou vypsány na jedné generované stránce.
Klienti v Pythonu mluví také HTTP a starý server MCP i řádkový protokol jsou pryč.
Odpověď dveří hlásí chyby od poslední odpovědi každou jednou a říká, zda krok proběhl.

## 0.16.1

<!-- machine draft, not reviewed -->
Kouzelná hůlka na pomalované vrstvě zdrží kliknutí na mnohem kratší dobu a na grafickou kartu čeká méně často na jedno kliknutí.
Žádný snímek startu Sary nedrží okno déle než třetinu sekundy.
Oddíl filtrů se otevře vedle nabídky Filtr a nabídka zůstane otevřená za ním.
Obrázek otevřený jako dokument si ponechá svůj obrázek na kartě v uvítacím okně.
Snímač textury razítkového přednastavení čte vlastní vzor razítka, takže křivka na něm sleduje texturu, kterou malujete.
Modul může přidat pole štětce přes dveře, stejně jako to nyní dělají tři vestavěná pole.
Při přiblížení na vrstvě s dvojnásobným rozlišením dokumentu ukazuje tah svůj detail už během malování a vrstva si detail drží pod maskou, ořezem i uvnitř izolované skupiny.
Malovací nástroj, který nebude malovat na generovanou vrstvu, řekne proč.
Sloučit dolů odmítne skupinu nebo generovanou vrstvu a duplikát si ponechá svůj druh, své členy a svou masku.
Posun vrstvy nahoru nebo dolů vezme s sebou členy skupiny a oříznutí i převzorkování vezmou masku skupiny.
Otevření souboru začíná bez výběru a bez dat modulů z posledního dokumentu.
Vrstva oříznutá na generovanou vrstvu se ukáže a přesun filtru je odmítnut tam, kde by bylo odmítnuto jeho připojení.
TIFF příliš velký pro formát je odmítnut dřív, než se zapíše, a transformace nikdy nepředá plochou matici.
Přidávací čip panelu palety drží vlastní barvy panelu a zámek vzatý uprostřed tahu tah ukončí.
Pro studenta `sara.py` nechá Saru otevřenou, když zavěsí, laboratoř Fourierovy transformace je jeden krok zpět a dveře posílají výpis stavu jen na požádání.
Test přechodu v EXR nese hodnotu čtyři a přečte ji zpět neoříznutou.

## 0.16.0

<!-- machine draft, not reviewed -->
Sara říká, kde naslouchají její dveře pro Python, takže se zápisník nebo skript připojí k už otevřené Saře.
`sara.py` je klient, kterého si student zkopíruje, pixely vrstvy procházejí dveřmi jako soubor `.npy` a jeden krok vypíše zásobník vrstev na jeden řádek.
V zápisníku buněčná magie `%%gmacs` přeloží jádro z buňky a spustí ho na plátně, s posuvníky pro jeho parametry, a krok redukce sečte vrstvu na GPU.
Pole může mezi buňkami žít na GPU a laboratoř Fourierovy transformace a zápisník Voronoi se dodávají jako lekce.
Zip pro Windows spouští Saru s otevřenými dveřmi a studentův modul běží v nainstalované verzi.
Dveře odpovídají krátkými řádky verdiktu, které umí přečíst i malý model, přijmou tah v souřadnicích dokumentu, vyplní mnohoúhelník nebo kruh a hlásí chyby enginu zevnitř Sary.
Soubory OpenRaster se otevírají se svými vrstvami a skupinami, Soubor, Importovat převezme jejich vrstvy a soubor, který Sara zapíše, se jinde otevře stejně.
Vrstva může mít dvojnásobné rozlišení dokumentu: ukládá se a otevírá, skládá, maluje, ořezává, mění velikost, přijímá filtry, vyplňuje, kopíruje a transformuje a plátno při přiblížení ukazuje její vlastní detail.
Tlačítko Zapéct vrátí takovou vrstvu na rozlišení dokumentu.
Přednastavení působí stejně bez ohledu na vlastní křivku přítlaku každého malíře a přednastavení z Krity se čte vůči vlastní křivce Krity.
Ctrl a kliknutí na náhled vrstvy vybere to, co vrstva obsahuje.
Dva prsty posouvají, přibližují a otáčejí plátno a tlačítka na těle pera lze přiřadit.
Během spouštění Sary pokrývá okno obraz posledního sezení s řádkem průběhu.
Na Windows bere první otisk tahu přítlak pera, malý štětec i kroužek Sary drží krok s perem, řádek ovladače jmenuje používaný ovladač a nečinná Sara bere méně než desetinu jádra.
Dialog kaleidoskopu se vejde na obrazovku 1280 na 1024, poznámku lze pořídit perem na řádku nabídky a panel se nikdy nezmění v obrázek, který nepřijímá vstup.
Vodnatý zvedací tah končí na svém vybledlém konci.
Maska skryje nový blok tam, kde skrývala prázdné plátno, kopie nechá masku za sebou, krabicové rozostření váží barvu jejím pokrytím a kbelík s vypnutou souvislostí vyplní každou shodu.
Hledání chyb přes celý strom opravilo, co našlo.

## 0.15.0

<!-- machine draft, not reviewed -->
Nový štětec, šumový štětec, maluje z textury, která rozhoduje, kam barva půjde, takže tah nikdy neukáže své otisky.
Jeho textura je jedno ze tří polí, štětiny, zrno nebo obrázek, a unáší se podél tahu, deformuje hrot a posouvá s sebou odstín a sytost.
Každý posuvník šumového štětce má vedle sebe posuvník náhodnosti, pro tah nebo pro otisk.
Naklonění pera rozšíří šumový štětec jako skutečný a rychlý tah táhne jeho texturu dál.
Dodává se první police přednastavení šumového štětce a přednastavení razítkového štětce se převede na šumový štětec a zpět.
Nastavení zvednutí ztenčuje barvu ke konci tahu jako vodu, u obou štětců.
Barva má výšku: malovací vrstva ji může nést, hustá barva roste k stropu a plátno ukazuje reliéf pod světlem.
Papír propůjčuje reliéfu svou zrnitost a hustá barva ji pohřbí a ve vlastnostech vrstvy lze vybrat tkaný podklad plátna, který se nikdy neopakuje.
Rozmazávání posouvá výšku s barvou a transformace i kopírování a vkládání nesou výšku také.
Export ukazuje reliéf, který ukazuje plátno.

## 0.14.1

<!-- machine draft, not reviewed -->
Na Windows pero maluje tam, kde je: Sara startuje na ovladači Wintab a ovladač je volbou v Předvolbách.
Text je ostrý při každém měřítku rozhraní, ne jen při jednom.
Akordy palety na numerické klávesnici fungují, rozbalovací seznam se zavře vlastním tlačítkem a plná historie kroků zpět už nevyhodí vyskakovací okno.
Režim prolnutí štětce nabízí každý režim a oba akordy výplně vyplňují.
Výplň, kouzelná hůlka, přechod, potvrzení transformace, první tah rozmazávání a připojení nebo použití filtru už neváznou a první tah sezení nečeká na své shadery.
Sara ukáže své uvítací okno před zbytkem spouštění a uvítací okno se zavře, jakmile je dokument vytvořen nebo otevřen.
Když horní lišta nemá místo, její druhý řádek přeteče za šipku, místo aby narostl další řádek, a rozbalovací seznamy se otevírají uvnitř okna.
Přivolaný panel lze zamknout otevřený, zůstane tam, kam ho tažení pustí, a kurzor je správně nad panelem, který je samostatným oknem.
Panel, který je samostatným oknem, už na Windows neklesá za hlavní okno a dialogy Sary nad ním zůstávají.
Počet zrcadel kaleidoskopu má ovládací prvek, na který perem dosáhnete.
Zavření okna filtru ho zruší, Připojit je volba uvnitř dialogu filtru a filtry jsou roztříděny do oddílů.
Jas a kontrast už nezmění barvu na zápornou a jejich krokovací tlačítka posouvají obraz stejně jako číslo.
Průběhový graf počítá každý pixel, který ukazuje.
Export sleduje tónový mapovač a nedávný dokument po zavření ukazuje svůj obrázek.
Krok zpět až tam, kde byl dokument uložen, smaže značku změny.
Horní lišta, stránka tabletu a výchozí rozvržení se vejdou na obrazovku širokou 1280 pixelů a řádek měřítka rozhraní jmenuje měřítko na obrazovce.
Rychlý tah tužkou je plný, rozstřik maluje až ke spodnímu okraji dokumentu a otisk dodávaného přednastavení při plném přítlaku vyplní svůj kroužek.
Otisk rozmazávání nestojí procesor víc než otisk barvy a nečinná Sara bere méně než desetinu jádra místo poloviny.
Zamrznutí zanechá v logu řádek, který říká, kde Sara byla.
Sara má vlastní verzi pro Windows, sestavenou z repozitáře.

## 0.14.0

<!-- machine draft, not reviewed -->
Rychlý tah sleduje křivku mezi vzorky pera místo řetězu rovných kousků.
Sara skládá jen to, co okno ukazuje, takže přiblížené plátno maluje a posouvá s menší prací.
Přepínání nástrojů je rychlejší: nic se nečte z disku, horní lišta se znovu přizpůsobí jen při změně svých ovládacích prvků a panel voleb nástroje následuje bez nového načtení rozvržení.
Stránka Výkon v Předvolbách sdružuje, co stojí GPU, s jedním přepínačem pro lehký režim, který při pohybu skládá pohled v poloviční velikosti.
Slabé GPU dostane lehký režim nabídnutý jednou, při startu.
Dialog Nový dokument říká, kolik paměti stojí jedna plná vrstva zvolené velikosti a hloubky.
Nápověda otevře uvnitř Sary příručku pro malíře se stránkami o malování, přednastaveních a barvě, vrstvách, výběrech a filtrech, tabletu, ukládání a zkratkách.
Obrázek se exportuje jako OpenRaster se svými vrstvami a exportované PNG nebo TIFF jmenuje svého autora a datum.
Nabídka exportu a nápověda k autorovi jmenují každý formát, který Sara zapisuje.
Režim texturování přednastavení z Krity maluje tak, jak ho maluje Krita, a maskovací štětec nese vlastní tok, otočení a rozptyl a skládá tak, jak říká jeho přednastavení.
Hrot trubky, který importér odmítne, nyní řekne proč, a nový import balíčku nabídne nahradit to, co z něj přišlo dřív.
Malování masky tmavým štětcem skryje vrstvu pod ním.
Připojený filtr lze sejmout tlačítkem minus nebo z nabídky řádku.
Barva vybraná kapátkem se přidá k nedávným barvám.
Dvojklik přejmenuje řádek vrstvy, na který dopadne, a řádek vrstvy, který nemůže jednat, je ztlumený a stisk odmítne.
Klávesa E zaškrtne řádek mazání, tah už neoznačí načtené přednastavení jako změněné a volba sloučení kouzelné hůlky už nejmenuje kapátko.
Otevření souboru už nepředá panelu vrstev vrstvu, která je už pryč.

## 0.13.0

<!-- machine draft, not reviewed -->
Masky vrstev: přidejte ji k vrstvě nebo skupině, malujte ji jakýmkoli štětcem a panel vrstev ji ukáže vedle náhledu.
Masku lze invertovat, vypnout, použít, smazat, vytvořit z výběru nebo převést zpět na výběr, každé jako jediný krok, který lze vrátit.
Filtry se připojují pod vrstvu nebo skupinu a zůstávají upravitelné po celý život dokumentu, takže rozostření nastavené v pondělí lze změnit v úterý.
Připojené filtry jsou v panelu vrstev vypsány pod svou vrstvou, přeřazují se tažením, vypínají se po jednom a slučují se do pixelů, až budete připraveni.
Připojený filtr nese vlastní masku, takže ho lze vmalovat i vymalovat.
Kliknutí na filtr otevře jeho ovládání v panelu voleb nástroje, a ne v dialogu, a dvojklik na řádek udělá totéž.
Obvyklé filtry se dodávají v základních modulech: přidání šumu, odšumění třemi způsoby, zostření a maska neostrosti, Gaussovo, pohybové a čočkové rozostření, práh, detekce hran, výška na normálovou mapu, reliéfní mapa a posun s přetečením pro malování dlaždicových textur.
Rozsah barev vybere barvu, přijme neurčitost a vybere každý texel v jejím rozsahu.
Kaleidoskop se dodává jako samostatný modul vedle krabicového rozostření.
Mapování gamutu sedí vedle tónového mapovače na stránce Zobrazení.
Moduly, Znovu načíst převezme modul, který jste změnili na disku, bez restartu Sary a znovu s ním sestaví jeho vrstvy, filtry a nabídky.
Jakýkoli panel lze akordem přivolat pod ukazatel a zase odejde, když se vzdálíte, a vyskakovací paleta dělá totéž pro sloty štětců.
Změna profilu zkratek už s sebou nemění výběr barvy.
Písmena napsaná do číselného pole už nezapíšou minimum.
Start bez ffmpeg už nevypíše chybu a popisek říká, co chybí.

## 0.12.1

<!-- machine draft, not reviewed -->
Vydání refaktoringu: strom za Sarou se přestěhoval do balíčků a na obrazovce se téměř nic nezměnilo.
Šest úprav pod Filtrem (jas a kontrast, odstín, sytost a světlost, křivky, úrovně, vyvážení barev a paleta) jsou nyní filtry základního modulu, se stejnými dialogy, živým náhledem a jedním krokem historie, a filtr modulu může přinést vlastní widget a klávesový akord.
Stránky Předvoleb se staví z jedné deklarativní vrstvy, takže každá stránka hledá, rozvrhuje a mění měřítko stejně a zamčený odstín tématu zůstane zamčený, když se pohne jiný řádek.
Ukázkové moduly se jmenují krabicové rozostření a tvrdé míchání a nic v programu nejmenuje kurz, podle kterého se kdysi jmenovaly.
Alfa je ladicí export, takže pád vypíše rámce skriptu, ve kterých skončil, a export poznámek nese log enginu.
Nedávný dokument v uvítacím okně znovu ukazuje svůj obrázek.
Dialog se otevře dost velký, aby ukázal svá vlastní tlačítka, a Alt s pravým tlačítkem mění velikost panelu k libovolnému rohu.
Export do PNG nebo TIFF zachová jasnou barvu, kterou pohled ořízl.
Prohlížeč filtrů se neotevře vyšší než obrazovka.
Druhý řádek horní lišty drží své ovládací prvky v pořadí prvního řádku.
Panel voleb nástroje vypisuje dynamiku štětce v pořadí jejích stránek.
Balíček Krity importovaný při aktivním nástroji přechodu už nezapíše štětec do nastavení přechodu.
Popisek, který zůstal viset nad lištou reference, odejde s ukazatelem.
Sara se měří: profilovací scénář a uložený základ času spuštění, počtu odeslání na tah a VRAM, který čte příští refaktoring.

## 0.12.0

<!-- machine draft, not reviewed -->
Při startu se otevře uvítací okno: vaše nedávné dokumenty jako náhledy s daty, rychlá nastavení a novinky.
Když sezení skončilo špatně, nabídka obnovy je horním řádkem panelu nedávných.
Uvítací okno lze vypnout a Nápověda ho vrátí.
Rychlá nastavení drží měřítko rozhraní, barevné téma, kalibraci přítlaku a přepínač vložených podoken, tytéž ovládací prvky, které drží Předvolby.
Seznam změn se dodává uvnitř verze a panel Novinky ukazuje, co se změnilo od verze, kterou jste naposledy spustili.
Testeři mohou zazipovat poznámky ze sezení z panelu Novinky a poslat je.
PNG a TIFF se exportují v 16 bitech, mezi 8bitovým a plovoucím exportem, a dialog si pamatuje hloubku pro každý formát.
16bitové PNG se při importu vrátí v plné hloubce.
Se Sarou se dodává dvacet základních štětců, mezi nimi airbrush, tužka, uhel, klínový fix, lavírování, dva rozmazávací štětce, dvě gumy, polotón, rozstřik a maskované tečkování.
Nová verze přidá přednastavení, která přináší, a ta, která jste smazali, nechá smazaná.
Každý balíček přednastavení nese svou licenci, ukázanou v popisku buňky a v panelu.
Balíčky a papíry dodávané uvnitř modulu se nainstalují při prvním spuštění.
Přednastavení Krity se importují věrněji: hroty trubek, mapa světlosti barevného hrotu, režimy texturování světlosti a výšky, dynamika velikosti a síly maskovacího štětce a poloměr a otupení rozmazávání.
Vzorkovat sloučené je přepínač, takže štětec čte buď viditelný zásobník, nebo jen aktivní vrstvu.
Nabídka Nastavení otevírá stránky profilu displeje, tabletu a zkratek a panely a rozvržení se přesunou pod Okno.
Vrstva má dialog přejmenování, který nese její poznámku, a pravý stisk na řádku vrstvy otevře její nabídku.
Načtení palety se zeptá, zda nahradit vzorníky, nebo je přidat, a paletu lze vyprázdnit.
Uložený dokument nese náhled, nakreslený ve skutečných barvách dokumentu.
Každý posuvník součinitele si znovu drží koncové nuly, takže 1.00 se čte jako 1.00.

## 0.11.1

<!-- machine draft, not reviewed -->
Tlačítka lišty už neberou klávesnici, takže mezerník posouvá plátno v okamžiku stisku.
Posuvník velikosti štětce nyní sahá pod jeden pixel, na logaritmické stupnici.
Držení Ctrl+Z opakuje krok zpět, takže dlouhý stisk rychle prochází historií.
Panel přednastavení se rozvrhne správně při prvním otevření, ne až po změně velikosti.
Panel Informace nyní ukazuje verzi, commit a datum sestavení.
Naučený předstih kurzoru, mezera mezi perem a kroužkem, je řádek v Předvolbách, který se učí sám, ve výchozím stavu Automaticky.
Druhé kliknutí na otevřený rozbalovací seznam ho zavře, místo aby ho znovu otevřelo.
Vedlejší pracovní plocha může opustit okno aplikace jako nativní okno systému.
Měřítko rozhraní sleduje monitor, na kterém okno sedí.

## 0.11.0

<!-- machine draft, not reviewed -->
Maskovací štětec: druhý hrot rozbije otisk na rozptyl menších značek, s vlastní velikostí a roztečí.
Hroty trubek, animované víceobrázkové štětce, které Krita nazývá .gih, se nyní importují a přehrávají své buňky.
Rozmazávací štětec nabírá barvu a nese ji podél tahu, drženou na GPU.
Dynamika barvy: odstín, sytost, jas, ztmavení a míchání mohou každé sledovat snímač.
Přicházejí papíry: vzory GIMP .pat a čtyři vestavěná zrna, s jasem, kontrastem a ořezem.
Dva režimy texturování, násobení a odečítání, nechávají papír tlačit do barvy různě.
Vějířový režim rozhazuje otisky kolem odemčeného rohu.
Deset slotů štětců dává vaše oblíbená přednastavení na dosah jednoho akordu.
Tok a Krytí se stávají jedním posuvníkem na liště.
Export přenáší barevný profil dokumentu do PNG, JPEG a TIFF.

## 0.10.1

<!-- machine draft, not reviewed -->
Panel nástrojů se při úzké šířce už sám nepřepíná na mřížku.
Kroužek štětce sleduje ukazatel s mnohem menším zpožděním.
Úrovně se nyní čtou jako histogram Photoshopu.
Oříznutí může plátno zvětšit a přiblížení zůstane, kde bylo.
Tažený nástroj může opustit svou skupinu v panelu nástrojů.
Štítky přednastavení lze vytvářet, přejmenovávat a odebírat.
Vedle tmavých palet se dodává světlá paleta Paper White.
Smazání přednastavení nebo palety se nejdřív zeptá.
Panel reference přijme soubor přetažený ze správce souborů.
Mřížka může jít až na jeden pixel a diagram CIE je nyní pořádná podkova.
Popisky se objevují bez kliknutí a titulky nabídek jsou kresleny v čitelné velikosti.

## 0.10.0

<!-- machine draft, not reviewed -->
Úrovně fungují jako ve Photoshopu, s živým histogramem.
Nástroj Záplata zahojí skvrnu v jednom kroku, který lze vrátit.
Štětce mohou malovat přes vzor papíru a vzor je samostatný zdroj.
Rozmazávací štětec čte sloučený snímek zásobníku.
Panel Reference drží obrázek vedle plátna a oba grafy ho sledují.
Balíčky přednastavení Krity se importují a jejich volby se mapují na volby Sary.
Výběr barvy získává tvary čtverec HSV, trojúhelník a HSL.
Oříznutí vymaže vše mimo obdélník.
Ctrl+mezerník maximalizuje panel s fokusem.

## 0.9.1

<!-- machine draft, not reviewed -->
Převážně vnitřní: dlouhé soubory byly rozděleny podle odpovědnosti, nikoli podle délky, a nástroje hůlka a přechod se přesunuly z jádra. Na obrazovce se nic nezměnilo.

## 0.9.0

<!-- machine draft, not reviewed -->
Přichází skriptování: modul nyní může dodat filtr, který se objeví v nabídce Filtr.
Obal pixelové funkce udělá z krátkého skriptu filtr s generovanými posuvníky.
Modul krabicového rozostření se dodává jako šablona pro psaní vlastních.
Průvodce první hodinou provede studenta od prázdného dokumentu k běžícímu filtru.

## 0.8.3

<!-- machine draft, not reviewed -->
Kurzor může ukazovat kroužek i systémový ukazatel zároveň.
Escape zruší úpravu, aniž by zavřel okno.
Tlačítko Přednastavení se druhým stiskem přepne a přednastavení ukazují své výchozí hodnoty.
Vyplnění vrstvy převádí přes barevný prostor dokumentu, takže barva dopadne tak, jak jste ji vybrali.

## 0.8.2

<!-- machine draft, not reviewed -->
Převážně vnitřní: shadery Sary se přesunuly do dialektu ve tvaru Pythonu, který se překládá na stejný výstup, s formátovačem a gramatikou. Na obrazovce se nic nezměnilo.

## 0.8.1

<!-- machine draft, not reviewed -->
Držení hranatých závorek velikosti se opakuje, takže štětec plynule roste a zmenšuje se.
Mezerník posouvá spolehlivě, i po kliknutí na tlačítko na liště.
Backspace vrátí posuvník na výchozí hodnotu.
Tlačítko Přednastavení otevře panel místo stísněné nabídky.
Tažení přes ikony oka přepne několik vrstev najednou.
Obrys obrázkového hrotu sleduje kurzor.
Úprava rozvržení panelů odvodí přednastavení, místo aby přepsala dodávané.
Řádek nastavení pera je ve výchozím stavu zapnutý.

## 0.8.0

<!-- machine draft, not reviewed -->
Přistává engine štětců a jeho dynamika: snímače, volby křivek, editor štětců a živé náhledy přednastavení.
Panel nástrojů se skládá do pěti kategorií s vysouvací nabídkou.
Nástroj Plechovka vyplní oblast na GPU.
Velikost obrazu převzorkuje každou vrstvu v jednom kroku, který lze vrátit.
Stisk H zrcadlí plátno.
Panel Zpět v historii vypisuje kroky, kterými se lze vrátit.
Guma nyní barvu odebírá, místo aby ji malovala.
Minimapa umí softproof ve stupních šedi.
První tah už při nulovém přítlaku nemaluje nic.

## 0.7.0

<!-- machine draft, not reviewed -->
Přichází nástroj Transformace s posunem, změnou velikosti, otočením a zkosením.
Panel Reference otevře obrázek vedle plátna s vlastním přiblížením a posunem.
Dodává se export do TIFF a nástroj přechodu si pamatuje své barvy.
Výběr barvy získává číselné posuvníky a protažený trojúhelník.
Vyvážení barev upravuje stíny, střední tóny a světla.
Výchozí hodnoty nového dokumentu se stávají přednastavením, které lze vybrat.
Dodává se pět přednastavení rozvržení panelů a úprava jedné odvodí kopii.
Softproof simuluje užší gamut.
Vrstvy lze seskupovat a sbalovat.

## 0.6.0

<!-- machine draft, not reviewed -->
Stránka Zobrazení v Předvolbách volí transformaci pohledu.
Panel Informace ukazuje řádky barev a dělí své statistiky do oddílů.
Každý panel dostane tlačítko skrytí.
Pochodující mravenci se nyní šíří rovnoměrně podél okraje výběru.
Klávesy hranatých závorek velikosti štětce lze objevit a jejich zkratky fungují z uloženého profilu.
K ovládání měřítka rozhraní se přidává posuvník velikosti písma.
