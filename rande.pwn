// ============================================================
//  Rande a vztahy pre GTA San Andreas (SA-MP)
//  Samostatny filterscript: pridaj "rande" do server.cfg -> filterscripts rande
//
//  Hrac -> /rande [ID] -> druhy hrac /prijatrande -> obaja dostanu cerveny kruh
//  na mape (nahodne miesto) -> ked obaja dorazia, spusti sa 15 min casomiera.
//  Rande sa da skor ukoncit /ukoncitrande. Po uplynuti casu, ak su obaja stale
//  na mieste, mozu si navzajom poslat /vztah [ID].
//  Ked druhy hrac vztah prijme (/prijatvztah), obaja dostanu rovnaku farbu nicku
//  (meno nad hlavou a v zozname hracov na TAB). Po /rozchod sa farba vrati spat.
// ============================================================
#include <a_samp>

// ---------- Nastavenia (lahko upravitelne) ----------
#define MAX_MIEST             30      // max. pocet miest na rande
#define RANDE_TRVANIE         900     // dlzka rande v sekundach (15 min)
#define RANDE_CAKANIE         600     // ako dlho sa caka, kym obaja dorazia (sek.) - potom sa rande zrusi
#define RANDE_PRIJAZD         8.0     // ako blizko k miestu musia prist (m)
#define RANDE_ZOSTAT          60.0    // v akej vzdialenosti od miesta musia byt na konci rande (m)
#define RANDE_POZVANKA_CAS    30000   // pozvanka na rande vyprsi po 30 s (ms)
#define VZTAH_POZVANKA_CAS    60000   // pozvanka do vztahu vyprsi po 60 s (ms)
#define VZTAH_OKNO            600     // ako dlho po rande mozu poslat /vztah (sek.)
#define VZTAH_VZDIALENOST     30.0    // max. vzdialenost hracov pri posielani /vztah (m)
#define MAX_VZTAHOV           300     // max. pocet vztahov v subore

// ---------- Miesta na rande (nacitavaju sa zo suboru rande_miesta.txt) ----------
new bool:MiestoAktivne[MAX_MIEST];
new Float:MiestoX[MAX_MIEST];
new Float:MiestoY[MAX_MIEST];
new Float:MiestoZ[MAX_MIEST];
new MiestoInt[MAX_MIEST];
new MiestoNazov[MAX_MIEST][32];

// ---------- Pozvanky ----------
new RandePozvankaOd[MAX_PLAYERS];     // kto ma pozval na rande
new RandePozvankaTimer[MAX_PLAYERS];
new VztahPozvankaOd[MAX_PLAYERS];     // kto mi poslal pozvanku do vztahu
new VztahPozvankaTimer[MAX_PLAYERS];

// ---------- Prebiehajuce rande ----------
// "hlavny" = hrac, ktory pozvanku prijal; na neho sa viaze casovac a udaje o rande
new RandePartner[MAX_PLAYERS];        // s kym som na rande
new RandeHlavny[MAX_PLAYERS];
new bool:RandePrisiel[MAX_PLAYERS];   // uz som dorazil na miesto
new PlayerText:RandeTD[MAX_PLAYERS];

new RandeStav[MAX_PLAYERS];           // (podla hlavneho) 1 = idu na miesto, 2 = rande prebieha
new RandeCas[MAX_PLAYERS];
new RandeTimer[MAX_PLAYERS];
new Float:RandeMX[MAX_PLAYERS];
new Float:RandeMY[MAX_PLAYERS];
new Float:RandeMZ[MAX_PLAYERS];
new RandeMInt[MAX_PLAYERS];
new RandeMNazov[MAX_PLAYERS][32];

// ---------- Vztahy ----------
new VztahMozny[MAX_PLAYERS];          // s kym mozem po rande uzavriet vztah
new VztahOknoTick[MAX_PLAYERS];
new VztahMeno[MAX_PLAYERS][MAX_PLAYER_NAME];  // meno partnera (prazdne = single)
new VztahFarba[MAX_PLAYERS];                 // spolocna farba nicku paru
new VztahPovodnaFarba[MAX_PLAYERS];          // farba nicku pred vztahom
new bool:VztahMaPovodnuFarbu[MAX_PLAYERS];

#define POCET_VZTAH_FARIEB 16
new VztahPaleta[POCET_VZTAH_FARIEB] = {
    0xFF4FA3FF, 0xFF2D55FF, 0xE040FBFF, 0x7C4DFFFF,
    0xFF5252FF, 0xFF6E40FF, 0xFF9100FF, 0xFFD740FF,
    0x00E676FF, 0x00B0FFFF, 0x00E5FFFF, 0x69F0AEFF,
    0xB388FFFF, 0xF48FB1FF, 0xFF80ABFF, 0xEA80FCFF
};

// ============================================================
//  Pomocne funkcie
// ============================================================
stock ParsujCislo(const text[], &poz, &vysledok)
{
    while(text[poz] == ' ') poz++;
    if(text[poz] < '0' || text[poz] > '9') return 0;
    vysledok = 0;
    while(text[poz] >= '0' && text[poz] <= '9')
    {
        if(vysledok < 1000000) vysledok = vysledok * 10 + (text[poz] - '0');
        poz++;
    }
    return 1;
}

stock DalsiToken(const text[], &poz, dest[], velkost)
{
    new i = 0;
    while(text[poz] == ' ' || text[poz] == '\r' || text[poz] == '\n') poz++;
    while(text[poz] != 0 && text[poz] != ' ' && text[poz] != '\r' && text[poz] != '\n')
    {
        if(i < velkost - 1) dest[i++] = text[poz];
        poz++;
    }
    dest[i] = 0;
    return i;
}

stock NajdiHracaPodlaMena(const meno[])
{
    new n[MAX_PLAYER_NAME];
    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        if(!IsPlayerConnected(i)) continue;
        GetPlayerName(i, n, sizeof(n));
        if(strcmp(n, meno, true) == 0) return i;
    }
    return INVALID_PLAYER_ID;
}

stock NulujHraca(playerid)
{
    RandePozvankaOd[playerid] = INVALID_PLAYER_ID;
    VztahPozvankaOd[playerid] = INVALID_PLAYER_ID;
    RandePartner[playerid] = INVALID_PLAYER_ID;
    RandeHlavny[playerid] = INVALID_PLAYER_ID;
    RandePrisiel[playerid] = false;
    RandeStav[playerid] = 0;
    RandeCas[playerid] = 0;
    VztahMozny[playerid] = INVALID_PLAYER_ID;
    VztahOknoTick[playerid] = 0;
    VztahMeno[playerid][0] = 0;
    VztahFarba[playerid] = 0;
    VztahPovodnaFarba[playerid] = 0;
    VztahMaPovodnuFarbu[playerid] = false;
}

// ============================================================
//  Miesta na rande
// ============================================================
stock PridajMiesto(const nazov[], Float:x, Float:y, Float:z, interior)
{
    for(new i = 0; i < MAX_MIEST; i++)
    {
        if(MiestoAktivne[i]) continue;
        MiestoAktivne[i] = true;
        MiestoX[i] = x;
        MiestoY[i] = y;
        MiestoZ[i] = z;
        MiestoInt[i] = interior;
        format(MiestoNazov[i], 32, "%s", nazov);
        return i;
    }
    return -1;
}

stock UlozMiesta()
{
    new File:f = fopen("rande_miesta.txt", io_write);
    if(!f) return 0;
    new riadok[128];
    for(new i = 0; i < MAX_MIEST; i++)
    {
        if(!MiestoAktivne[i]) continue;
        format(riadok, sizeof(riadok), "%.3f %.3f %.3f %d %s\r\n", MiestoX[i], MiestoY[i], MiestoZ[i], MiestoInt[i], MiestoNazov[i]);
        fwrite(f, riadok);
    }
    fclose(f);
    return 1;
}

stock NacitajMiesta()
{
    new pocet = 0;
    new File:f = fopen("rande_miesta.txt", io_read);
    if(f)
    {
        new riadok[128], tok[32], poz, nazov[32], n;
        while(fread(f, riadok))
        {
            poz = 0;
            if(!DalsiToken(riadok, poz, tok, sizeof(tok))) continue;
            new Float:x = floatstr(tok);
            DalsiToken(riadok, poz, tok, sizeof(tok)); new Float:y = floatstr(tok);
            DalsiToken(riadok, poz, tok, sizeof(tok)); new Float:z = floatstr(tok);
            DalsiToken(riadok, poz, tok, sizeof(tok)); new interior = strval(tok);

            while(riadok[poz] == ' ') poz++;
            n = 0;
            while(riadok[poz] != 0 && riadok[poz] != '\r' && riadok[poz] != '\n' && n < 31) nazov[n++] = riadok[poz++];
            nazov[n] = 0;
            if(n == 0) format(nazov, sizeof(nazov), "Miesto na rande");

            if(PridajMiesto(nazov, x, y, z, interior) != -1) pocet++;
        }
        fclose(f);
    }
    if(pocet == 0)
    {
        // predvolene miesta (kym admin nepridá vlastne cez /randemiesto)
        PridajMiesto("Alhambra klub", 1832.3, -1682.4, 13.4, 0);
        PridajMiesto("Well Stacked Pizza", 2105.4, -1806.4, 13.5, 0);
    }
    return pocet;
}

stock PocetMiest()
{
    new pocet = 0;
    for(new i = 0; i < MAX_MIEST; i++)
    {
        if(MiestoAktivne[i]) pocet++;
    }
    return pocet;
}

// ============================================================
//  Vztahy - ukladanie do suboru vztahy.txt
//  riadok = "meno1 meno2 RRGGBB" (farba je spolocna pre oboch)
// ============================================================
stock HexNaFarbu(const text[])
{
    new farba = 0, i = 0;
    while(text[i] != 0)
    {
        new c = text[i], v = -1;
        if(c >= '0' && c <= '9') v = c - '0';
        else if(c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if(c >= 'A' && c <= 'F') v = c - 'A' + 10;
        else break;
        farba = (farba << 4) | v;
        i++;
    }
    if(i != 6 && i != 8) return 0;
    if(i == 6) farba = (farba << 8) | 0xFF;
    else farba = (farba & 0xFFFFFF00) | 0xFF;
    return farba;
}

stock FarbaDoTextu(farba, dest[], velkost)
{
    new cisla[] = "0123456789abcdef";
    new r = (farba >>> 24) & 0xFF;
    new g = (farba >>> 16) & 0xFF;
    new b = (farba >>> 8) & 0xFF;
    if(velkost < 7) { dest[0] = 0; return 0; }
    dest[0] = cisla[(r >>> 4) & 0xF];
    dest[1] = cisla[r & 0xF];
    dest[2] = cisla[(g >>> 4) & 0xF];
    dest[3] = cisla[g & 0xF];
    dest[4] = cisla[(b >>> 4) & 0xF];
    dest[5] = cisla[b & 0xF];
    dest[6] = 0;
    return 1;
}

stock HashniMeno(h, const meno[])
{
    for(new i = 0; meno[i] != 0; i++)
    {
        new c = meno[i];
        if(c >= 'A' && c <= 'Z') c += 32;
        h = (h * 33) + c;
    }
    return h;
}

// Stala farba z mien, ked stary subor este farbu nema. Obe poradia mien daju to iste.
stock FarbaZMien(const a[], const b[])
{
    new h = 5381;
    if(strcmp(a, b, true) <= 0)
    {
        h = HashniMeno(h, a);
        h = HashniMeno(h, b);
    }
    else
    {
        h = HashniMeno(h, b);
        h = HashniMeno(h, a);
    }
    h = h & 0x7FFFFFFF;
    return VztahPaleta[h % POCET_VZTAH_FARIEB];
}

stock OznacFarbyZoSuboru(bool:obsadena[])
{
    new File:f = fopen("vztahy.txt", io_read);
    if(!f) return 0;
    new riadok[96], poz, a[MAX_PLAYER_NAME], b[MAX_PLAYER_NAME], c[16];
    while(fread(f, riadok))
    {
        poz = 0;
        if(!DalsiToken(riadok, poz, a, sizeof(a))) continue;
        if(!DalsiToken(riadok, poz, b, sizeof(b))) continue;
        new farba = 0;
        if(DalsiToken(riadok, poz, c, sizeof(c))) farba = HexNaFarbu(c);
        if(farba == 0) farba = FarbaZMien(a, b);
        for(new i = 0; i < POCET_VZTAH_FARIEB; i++)
        {
            if(farba == VztahPaleta[i]) obsadena[i] = true;
        }
    }
    fclose(f);
    return 1;
}

stock VyberFarbuParu()
{
    new bool:obsadena[POCET_VZTAH_FARIEB];
    OznacFarbyZoSuboru(obsadena);
    new volne[POCET_VZTAH_FARIEB], pocet = 0;
    for(new i = 0; i < POCET_VZTAH_FARIEB; i++)
    {
        if(!obsadena[i]) volne[pocet++] = VztahPaleta[i];
    }
    if(pocet == 0) return VztahPaleta[random(POCET_VZTAH_FARIEB)];
    return volne[random(pocet)];
}

// Premaluje nick. Ak medzitym server nastavil inu farbu, tu si pamata a po rozchode ju vrati.
stock AplikujFarbuVztahu(playerid)
{
    if(!IsPlayerConnected(playerid)) return 0;
    if(VztahMeno[playerid][0] == 0 || VztahFarba[playerid] == 0) return 0;

    new aktualna = GetPlayerColor(playerid);
    if(aktualna != VztahFarba[playerid] && aktualna != 0)
    {
        VztahPovodnaFarba[playerid] = aktualna;
        VztahMaPovodnuFarbu[playerid] = true;
    }
    if(aktualna != VztahFarba[playerid]) SetPlayerColor(playerid, VztahFarba[playerid]);
    return 1;
}

stock VratFarbuPredVztahom(playerid)
{
    if(!IsPlayerConnected(playerid)) return 0;
    // rozchod uz ma zmazane meno; pri vypnuti skriptu vracame farbu len tomu, komu sme ju zmenili
    new aktualna = GetPlayerColor(playerid);
    new bool:vratit = false;
    if(VztahMeno[playerid][0] == 0) vratit = true;
    else if(VztahFarba[playerid] != 0 && aktualna == VztahFarba[playerid]) vratit = true;

    if(vratit)
    {
        new farba = 0xFFFFFFFF;
        if(VztahMaPovodnuFarbu[playerid] && VztahPovodnaFarba[playerid] != 0)
            farba = VztahPovodnaFarba[playerid];
        SetPlayerColor(playerid, farba);
    }
    VztahMaPovodnuFarbu[playerid] = false;
    VztahPovodnaFarba[playerid] = 0;
    return 1;
}

stock NajdiVztah(const meno[], partner[], velkost, &farba)
{
    partner[0] = 0;
    farba = 0;
    new File:f = fopen("vztahy.txt", io_read);
    if(!f) return 0;
    new riadok[96], poz, a[MAX_PLAYER_NAME], b[MAX_PLAYER_NAME], c[16], najdene = 0;
    while(fread(f, riadok))
    {
        poz = 0;
        if(!DalsiToken(riadok, poz, a, sizeof(a))) continue;
        if(!DalsiToken(riadok, poz, b, sizeof(b))) continue;
        new zhoda = 0;
        if(strcmp(a, meno, true) == 0) { format(partner, velkost, "%s", b); zhoda = 1; }
        else if(strcmp(b, meno, true) == 0) { format(partner, velkost, "%s", a); zhoda = 1; }
        if(!zhoda) continue;
        if(DalsiToken(riadok, poz, c, sizeof(c))) farba = HexNaFarbu(c);
        if(farba == 0) farba = FarbaZMien(a, b);
        najdene = 1;
        break;
    }
    fclose(f);
    return najdene;
}

stock UlozVztah(const meno1[], const meno2[], farba)
{
    new File:f = fopen("vztahy.txt", io_append);
    if(!f) return 0;
    new riadok[96], hex[8];
    FarbaDoTextu(farba, hex, sizeof(hex));
    format(riadok, sizeof(riadok), "%s %s %s\r\n", meno1, meno2, hex);
    fwrite(f, riadok);
    fclose(f);
    return 1;
}

// Odstrani zo suboru vsetky vztahy, v ktorych vystupuje dane meno
stock ZrusVztahVSubore(const meno[])
{
    static riadky[MAX_VZTAHOV][80];
    new pocet = 0;
    new File:f = fopen("vztahy.txt", io_read);
    if(!f) return 0;
    new riadok[96], poz, a[MAX_PLAYER_NAME], b[MAX_PLAYER_NAME], c[16], hex[8];
    while(fread(f, riadok))
    {
        poz = 0;
        if(!DalsiToken(riadok, poz, a, sizeof(a))) continue;
        if(!DalsiToken(riadok, poz, b, sizeof(b))) continue;
        if(strcmp(a, meno, true) == 0 || strcmp(b, meno, true) == 0) continue;
        new farba = 0;
        if(DalsiToken(riadok, poz, c, sizeof(c))) farba = HexNaFarbu(c);
        if(farba == 0) farba = FarbaZMien(a, b);
        FarbaDoTextu(farba, hex, sizeof(hex));
        if(pocet < MAX_VZTAHOV)
        {
            format(riadky[pocet], sizeof(riadky[]), "%s %s %s\r\n", a, b, hex);
            pocet++;
        }
    }
    fclose(f);

    f = fopen("vztahy.txt", io_write);
    if(!f) return 0;
    for(new i = 0; i < pocet; i++) fwrite(f, riadky[i]);
    fclose(f);
    return 1;
}

stock NacitajVztahHraca(playerid)
{
    new meno[MAX_PLAYER_NAME], farba;
    GetPlayerName(playerid, meno, sizeof(meno));
    if(NajdiVztah(meno, VztahMeno[playerid], MAX_PLAYER_NAME, farba))
        VztahFarba[playerid] = farba;
    else
        VztahFarba[playerid] = 0;
}

// ============================================================
//  Pozvanky
// ============================================================
stock ZrusPozvankuRande(cielid)
{
    if(RandePozvankaOd[cielid] != INVALID_PLAYER_ID) KillTimer(RandePozvankaTimer[cielid]);
    RandePozvankaOd[cielid] = INVALID_PLAYER_ID;
}

stock ZrusPozvankuVztah(cielid)
{
    if(VztahPozvankaOd[cielid] != INVALID_PLAYER_ID) KillTimer(VztahPozvankaTimer[cielid]);
    VztahPozvankaOd[cielid] = INVALID_PLAYER_ID;
}

forward RandePozvankaVyprsala(cielid);
public RandePozvankaVyprsala(cielid)
{
    new od = RandePozvankaOd[cielid];
    RandePozvankaOd[cielid] = INVALID_PLAYER_ID;
    if(IsPlayerConnected(cielid)) SendClientMessage(cielid, 0xFFFF00FF, "[RANDE] Pozvanka na rande vyprsala.");
    if(od != INVALID_PLAYER_ID && IsPlayerConnected(od)) SendClientMessage(od, 0xFFFF00FF, "[RANDE] Tvoja pozvanka na rande vyprsala bez odpovede.");
    return 1;
}

forward VztahPozvankaVyprsala(cielid);
public VztahPozvankaVyprsala(cielid)
{
    new od = VztahPozvankaOd[cielid];
    VztahPozvankaOd[cielid] = INVALID_PLAYER_ID;
    if(IsPlayerConnected(cielid)) SendClientMessage(cielid, 0xFFFF00FF, "[VZTAH] Pozvanka do vztahu vyprsala.");
    if(od != INVALID_PLAYER_ID && IsPlayerConnected(od)) SendClientMessage(od, 0xFFFF00FF, "[VZTAH] Tvoja pozvanka do vztahu vyprsala bez odpovede.");
    return 1;
}

// ============================================================
//  Rande
// ============================================================
stock RandeVycisti(playerid, sprava[])
{
    RandePartner[playerid] = INVALID_PLAYER_ID;
    RandeHlavny[playerid] = INVALID_PLAYER_ID;
    RandePrisiel[playerid] = false;
    if(!IsPlayerConnected(playerid)) return 1;
    DisablePlayerRaceCheckpoint(playerid);
    PlayerTextDrawHide(playerid, RandeTD[playerid]);
    SendClientMessage(playerid, 0xFFFF00FF, sprava);
    return 1;
}

// Ukonci rande pre oboch ucastnikov
stock UkonciRande(playerid, sprava[])
{
    new p = RandePartner[playerid];
    if(p == INVALID_PLAYER_ID) return 0;
    new h = RandeHlavny[playerid];
    KillTimer(RandeTimer[h]);
    RandeStav[h] = 0;
    RandeVycisti(playerid, sprava);
    RandeVycisti(p, sprava);
    return 1;
}

stock VytvorTextdraw(playerid)
{
    RandeTD[playerid] = CreatePlayerTextDraw(playerid, 268.0, 8.0, "RANDE");
    PlayerTextDrawFont(playerid, RandeTD[playerid], 1);
    PlayerTextDrawLetterSize(playerid, RandeTD[playerid], 0.45, 1.8);
    PlayerTextDrawSetOutline(playerid, RandeTD[playerid], 1);
    PlayerTextDrawColor(playerid, RandeTD[playerid], 0xFFFFFFFF);
}

forward VztahFarbaPoPripojeni(playerid);
public VztahFarbaPoPripojeni(playerid)
{
    AplikujFarbuVztahu(playerid);
    return 1;
}

forward RandeTik(h);
public RandeTik(h)
{
    new p = RandePartner[h];
    if(p == INVALID_PLAYER_ID) return 1;
    if(!IsPlayerConnected(h) || !IsPlayerConnected(p))
    {
        UkonciRande(h, "[RANDE] Rande bolo ukoncene, partner odisiel.");
        return 1;
    }

    // ---- Stav 1: obaja idu na miesto ----
    if(RandeStav[h] == 1)
    {
        RandeCas[h]++;
        new ids[2];
        ids[0] = h;
        ids[1] = p;
        for(new k = 0; k < 2; k++)
        {
            new x = ids[k];
            if(RandePrisiel[x]) continue;
            if(GetPlayerInterior(x) == RandeMInt[h] && IsPlayerInRangeOfPoint(x, RANDE_PRIJAZD, RandeMX[h], RandeMY[h], RandeMZ[h]))
            {
                RandePrisiel[x] = true;
                DisablePlayerRaceCheckpoint(x);
                SendClientMessage(x, 0x00FF00FF, "[RANDE] Dorazil si na miesto. Cakas na partnera.");
            }
        }

        if(RandePrisiel[h] && RandePrisiel[p])
        {
            RandeStav[h] = 2;
            RandeCas[h] = RANDE_TRVANIE;
            SendClientMessage(h, 0xFF66CCFF, "[RANDE] Obaja ste dorazili! Rande zacalo (15 minut). Skor ho ukoncis prikazom /ukoncitrande.");
            SendClientMessage(p, 0xFF66CCFF, "[RANDE] Obaja ste dorazili! Rande zacalo (15 minut). Skor ho ukoncis prikazom /ukoncitrande.");
            PlayerTextDrawShow(h, RandeTD[h]);
            PlayerTextDrawShow(p, RandeTD[p]);
        }
        else if(RandeCas[h] >= RANDE_CAKANIE)
        {
            UkonciRande(h, "[RANDE] Rande bolo zrusene - nedorazili ste vcas obaja.");
        }
        return 1;
    }

    // ---- Stav 2: rande prebieha, odpocitavanie ----
    if(RandeStav[h] == 2)
    {
        RandeCas[h]--;
        if(RandeCas[h] > 0)
        {
            new text[40];
            format(text, sizeof(text), "~r~RANDE ~w~%02d:%02d", RandeCas[h] / 60, RandeCas[h] % 60);
            PlayerTextDrawSetString(h, RandeTD[h], text);
            PlayerTextDrawSetString(p, RandeTD[p], text);
            return 1;
        }

        // cas vyprsal - su obaja stale na mieste?
        new bool:ostali = true;
        if(GetPlayerInterior(h) != RandeMInt[h] || !IsPlayerInRangeOfPoint(h, RANDE_ZOSTAT, RandeMX[h], RandeMY[h], RandeMZ[h])) ostali = false;
        if(GetPlayerInterior(p) != RandeMInt[h] || !IsPlayerInRangeOfPoint(p, RANDE_ZOSTAT, RandeMX[h], RandeMY[h], RandeMZ[h])) ostali = false;

        UkonciRande(h, "[RANDE] Rande skoncilo. Dakujeme, ze ste si ho uzili!");

        if(ostali)
        {
            VztahMozny[h] = p;
            VztahMozny[p] = h;
            VztahOknoTick[h] = GetTickCount();
            VztahOknoTick[p] = GetTickCount();
            SendClientMessage(h, 0xFF66CCFF, "[RANDE] Ak chcete, mozes pozvat partnera do vztahu: /vztah [ID]");
            SendClientMessage(p, 0xFF66CCFF, "[RANDE] Ak chcete, mozes pozvat partnera do vztahu: /vztah [ID]");
        }
        return 1;
    }
    return 1;
}

// ============================================================
//  Callbacky
// ============================================================
public OnFilterScriptInit()
{
    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        NulujHraca(i);
        if(IsPlayerConnected(i))
        {
            VytvorTextdraw(i);
            NacitajVztahHraca(i);
            AplikujFarbuVztahu(i);
        }
    }
    new pocet = NacitajMiesta();
    printf("[RANDE] Filterscript nacitany. Miest zo suboru: %d, aktivnych miest: %d", pocet, PocetMiest());
    return 1;
}

public OnFilterScriptExit()
{
    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        if(!IsPlayerConnected(i)) continue;
        UkonciRande(i, "[RANDE] Skript bol vypnuty, rande ukoncene.");
        VratFarbuPredVztahom(i);
        PlayerTextDrawDestroy(i, RandeTD[i]);
    }
    return 1;
}

public OnPlayerConnect(playerid)
{
    NulujHraca(playerid);
    VytvorTextdraw(playerid);
    NacitajVztahHraca(playerid);
    if(VztahMeno[playerid][0] != 0)
    {
        new text[96];
        format(text, sizeof(text), "[VZTAH] Si vo vztahu s hracom %s. Mate rovnaku farbu nicku.", VztahMeno[playerid]);
        SendClientMessage(playerid, 0xFF66CCFF, text);
        SetTimerEx("VztahFarbaPoPripojeni", 1000, false, "i", playerid);
    }
    return 1;
}

public OnPlayerSpawn(playerid)
{
    if(VztahMeno[playerid][0] != 0)
        SetTimerEx("VztahFarbaPoPripojeni", 1000, false, "i", playerid);
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    UkonciRande(playerid, "[RANDE] Rande bolo ukoncene - partner odisiel zo servera.");
    ZrusPozvankuRande(playerid);
    ZrusPozvankuVztah(playerid);
    return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
    UkonciRande(playerid, "[RANDE] Rande bolo prerusene - jeden z vas zomrel.");
    return 1;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
    // ---------- /rande [ID] ----------
    if(strcmp("/rande", cmdtext, true, 6) == 0 && (cmdtext[6] == 0 || cmdtext[6] == ' '))
    {
        new poz = 6, id;
        if(!ParsujCislo(cmdtext, poz, id)) return SendClientMessage(playerid, 0xFFFF00FF, "Pouzitie: /rande [ID hraca]");
        if(id < 0 || id >= MAX_PLAYERS || !IsPlayerConnected(id)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Hrac s tymto ID nie je na serveri.");
        if(id == playerid) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemozes pozvat sam seba.");
        if(RandePartner[playerid] != INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Uz si na rande. Skonci ho prikazom /ukoncitrande.");
        if(RandePartner[id] != INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento hrac je prave na rande.");
        if(RandePozvankaOd[id] != INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento hrac uz ma pozvanku, pockaj chvilu.");
        if(PocetMiest() == 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Na serveri nie su nastavene ziadne miesta na rande.");

        RandePozvankaOd[id] = playerid;
        RandePozvankaTimer[id] = SetTimerEx("RandePozvankaVyprsala", RANDE_POZVANKA_CAS, false, "i", id);

        new menoOd[MAX_PLAYER_NAME], menoCiel[MAX_PLAYER_NAME], sprava[128];
        GetPlayerName(playerid, menoOd, sizeof(menoOd));
        GetPlayerName(id, menoCiel, sizeof(menoCiel));
        format(sprava, sizeof(sprava), "[RANDE] %s ta pozyva na rande! Napis /prijatrande alebo /odmietnutrande (vyprsi o 30 sekund).", menoOd);
        SendClientMessage(id, 0xFF66CCFF, sprava);
        format(sprava, sizeof(sprava), "[RANDE] Pozvanka na rande bola odoslana hracovi %s.", menoCiel);
        SendClientMessage(playerid, 0xFF66CCFF, sprava);
        return 1;
    }

    if(strcmp("/odmietnutrande", cmdtext, true) == 0)
    {
        new od = RandePozvankaOd[playerid];
        if(od == INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemas ziadnu pozvanku na rande.");
        ZrusPozvankuRande(playerid);
        SendClientMessage(playerid, 0xFFFF00FF, "[RANDE] Pozvanku si odmietol.");
        if(IsPlayerConnected(od)) SendClientMessage(od, 0xFFFF00FF, "[RANDE] Tvoju pozvanku na rande niekto odmietol.");
        return 1;
    }

    if(strcmp("/prijatrande", cmdtext, true) == 0)
    {
        new od = RandePozvankaOd[playerid];
        if(od == INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemas ziadnu pozvanku na rande.");
        ZrusPozvankuRande(playerid);

        if(!IsPlayerConnected(od)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Hrac, ktory ta pozval, uz nie je na serveri.");
        if(RandePartner[od] != INVALID_PLAYER_ID || RandePartner[playerid] != INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Niekto z vas je uz na rande.");

        new pocet = PocetMiest();
        if(pocet == 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Na serveri nie su nastavene ziadne miesta na rande.");

        // nahodny vyber miesta
        new vyber = random(pocet), k = -1;
        for(new i = 0; i < MAX_MIEST; i++)
        {
            if(!MiestoAktivne[i]) continue;
            if(vyber == 0) { k = i; break; }
            vyber--;
        }
        if(k == -1) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nepodarilo sa vybrat miesto.");

        new h = playerid; // hlavny = ten, kto prijal
        RandePartner[h] = od;
        RandePartner[od] = h;
        RandeHlavny[h] = h;
        RandeHlavny[od] = h;
        RandePrisiel[h] = false;
        RandePrisiel[od] = false;
        RandeStav[h] = 1;
        RandeCas[h] = 0;
        RandeMX[h] = MiestoX[k];
        RandeMY[h] = MiestoY[k];
        RandeMZ[h] = MiestoZ[k];
        RandeMInt[h] = MiestoInt[k];
        format(RandeMNazov[h], 32, "%s", MiestoNazov[k]);

        DisablePlayerRaceCheckpoint(h);
        DisablePlayerRaceCheckpoint(od);
        SetPlayerRaceCheckpoint(h, 2, MiestoX[k], MiestoY[k], MiestoZ[k], MiestoX[k], MiestoY[k], MiestoZ[k], 4.0);
        SetPlayerRaceCheckpoint(od, 2, MiestoX[k], MiestoY[k], MiestoZ[k], MiestoX[k], MiestoY[k], MiestoZ[k], 4.0);

        RandeTimer[h] = SetTimerEx("RandeTik", 1000, true, "i", h);

        new menoH[MAX_PLAYER_NAME], menoOd[MAX_PLAYER_NAME], sprava[160];
        GetPlayerName(h, menoH, sizeof(menoH));
        GetPlayerName(od, menoOd, sizeof(menoOd));
        format(sprava, sizeof(sprava), "[RANDE] %s prijal(a) tvoju pozvanku! Miesto: %s - chod na cerveny kruh na mape (mate 10 minut).", menoH, RandeMNazov[h]);
        SendClientMessage(od, 0xFF66CCFF, sprava);
        format(sprava, sizeof(sprava), "[RANDE] Rande s %s! Miesto: %s - chod na cerveny kruh na mape (mate 10 minut).", menoOd, RandeMNazov[h]);
        SendClientMessage(h, 0xFF66CCFF, sprava);
        return 1;
    }

    if(strcmp("/ukoncitrande", cmdtext, true) == 0)
    {
        if(RandePartner[playerid] == INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nie si na ziadnom rande.");
        new meno[MAX_PLAYER_NAME], sprava[128];
        GetPlayerName(playerid, meno, sizeof(meno));
        format(sprava, sizeof(sprava), "[RANDE] Rande bolo ukoncene (ukoncil(a): %s).", meno);
        UkonciRande(playerid, sprava);
        return 1;
    }

    // ---------- /vztah [ID] ----------
    if(strcmp("/vztah", cmdtext, true, 6) == 0 && (cmdtext[6] == 0 || cmdtext[6] == ' '))
    {
        new poz = 6, id;
        if(!ParsujCislo(cmdtext, poz, id))
        {
            // bez ID = informacia o stave
            if(VztahMeno[playerid][0] != 0)
            {
                new sprava[128];
                if(NajdiHracaPodlaMena(VztahMeno[playerid]) != INVALID_PLAYER_ID) format(sprava, sizeof(sprava), "[VZTAH] Si vo vztahu s %s (je online). Mate rovnaku farbu nicku. Ukoncit: /rozchod", VztahMeno[playerid]);
                else format(sprava, sizeof(sprava), "[VZTAH] Si vo vztahu s %s (je offline). Mate rovnaku farbu nicku. Ukoncit: /rozchod", VztahMeno[playerid]);
                return SendClientMessage(playerid, 0xFF66CCFF, sprava);
            }
            return SendClientMessage(playerid, 0xFFFF00FF, "[VZTAH] Nie si vo vztahu. Po uspesnom rande mozes pouzit: /vztah [ID hraca]");
        }

        if(id < 0 || id >= MAX_PLAYERS || !IsPlayerConnected(id)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Hrac s tymto ID nie je na serveri.");
        if(id == playerid) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemozes poslat pozvanku sam sebe.");
        if(VztahMozny[playerid] != id || VztahMozny[id] != playerid) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Vztah mozes navrhnut len hracovi, s ktorym si prave dokoncil rande.");
        if((GetTickCount() - VztahOknoTick[playerid]) > VZTAH_OKNO * 1000)
        {
            VztahMozny[playerid] = INVALID_PLAYER_ID;
            if(VztahMozny[id] == playerid) VztahMozny[id] = INVALID_PLAYER_ID;
            return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Cas na navrhnutie vztahu po rande uz vyprsal.");
        }
        if(VztahMeno[playerid][0] != 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Uz si vo vztahu. Najprv sa musis rozist (/rozchod).");
        if(VztahMeno[id][0] != 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento hrac uz je vo vztahu.");
        if(VztahPozvankaOd[id] != INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento hrac uz ma pozvanku do vztahu.");

        new Float:x, Float:y, Float:z;
        GetPlayerPos(id, x, y, z);
        if(GetPlayerInterior(playerid) != GetPlayerInterior(id) || !IsPlayerInRangeOfPoint(playerid, VZTAH_VZDIALENOST, x, y, z))
        {
            return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Musite byt blizko seba.");
        }

        VztahPozvankaOd[id] = playerid;
        VztahPozvankaTimer[id] = SetTimerEx("VztahPozvankaVyprsala", VZTAH_POZVANKA_CAS, false, "i", id);

        new menoOd[MAX_PLAYER_NAME], menoCiel[MAX_PLAYER_NAME], sprava[128];
        GetPlayerName(playerid, menoOd, sizeof(menoOd));
        GetPlayerName(id, menoCiel, sizeof(menoCiel));
        format(sprava, sizeof(sprava), "[VZTAH] %s ta pozyva do vztahu! Napis /prijatvztah alebo /odmietnutvztah (vyprsi o 60 sekund).", menoOd);
        SendClientMessage(id, 0xFF66CCFF, sprava);
        format(sprava, sizeof(sprava), "[VZTAH] Pozvanka do vztahu bola odoslana hracovi %s.", menoCiel);
        SendClientMessage(playerid, 0xFF66CCFF, sprava);
        return 1;
    }

    if(strcmp("/odmietnutvztah", cmdtext, true) == 0)
    {
        new od = VztahPozvankaOd[playerid];
        if(od == INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemas ziadnu pozvanku do vztahu.");
        ZrusPozvankuVztah(playerid);
        SendClientMessage(playerid, 0xFFFF00FF, "[VZTAH] Pozvanku si odmietol.");
        if(IsPlayerConnected(od)) SendClientMessage(od, 0xFFFF00FF, "[VZTAH] Tvoju pozvanku do vztahu niekto odmietol.");
        return 1;
    }

    if(strcmp("/prijatvztah", cmdtext, true) == 0)
    {
        new od = VztahPozvankaOd[playerid];
        if(od == INVALID_PLAYER_ID) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nemas ziadnu pozvanku do vztahu.");
        ZrusPozvankuVztah(playerid);

        if(!IsPlayerConnected(od)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Hrac, ktory ta pozval, uz nie je na serveri.");
        if(VztahMeno[playerid][0] != 0 || VztahMeno[od][0] != 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Niekto z vas je uz vo vztahu.");

        new meno1[MAX_PLAYER_NAME], meno2[MAX_PLAYER_NAME];
        GetPlayerName(od, meno1, sizeof(meno1));
        GetPlayerName(playerid, meno2, sizeof(meno2));

        new farba = VyberFarbuParu();
        format(VztahMeno[od], MAX_PLAYER_NAME, "%s", meno2);
        format(VztahMeno[playerid], MAX_PLAYER_NAME, "%s", meno1);
        VztahFarba[od] = farba;
        VztahFarba[playerid] = farba;
        AplikujFarbuVztahu(od);
        AplikujFarbuVztahu(playerid);

        VztahMozny[od] = INVALID_PLAYER_ID;
        VztahMozny[playerid] = INVALID_PLAYER_ID;

        new sprava[144];
        if(!UlozVztah(meno1, meno2, farba))
        {
            SendClientMessage(playerid, 0xFF0000FF, "[VZTAH] Vztah plati, ale nepodarilo sa ho ulozit do suboru.");
            SendClientMessage(od, 0xFF0000FF, "[VZTAH] Vztah plati, ale nepodarilo sa ho ulozit do suboru.");
        }
        format(sprava, sizeof(sprava), "[VZTAH] %s a %s su odteraz vo vztahu! Ich nick ma rovnaku farbu.", meno1, meno2);
        SendClientMessageToAll(0xFF66CCFF, sprava);
        return 1;
    }

    if(strcmp("/rozchod", cmdtext, true) == 0)
    {
        if(VztahMeno[playerid][0] == 0) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Nie si vo vztahu.");
        new meno[MAX_PLAYER_NAME], partnerMeno[MAX_PLAYER_NAME];
        GetPlayerName(playerid, meno, sizeof(meno));
        format(partnerMeno, sizeof(partnerMeno), "%s", VztahMeno[playerid]);

        ZrusVztahVSubore(meno);

        new partner = NajdiHracaPodlaMena(partnerMeno);
        VztahMeno[playerid][0] = 0;
        VztahFarba[playerid] = 0;
        VratFarbuPredVztahom(playerid);

        if(partner != INVALID_PLAYER_ID)
        {
            VztahMeno[partner][0] = 0;
            VztahFarba[partner] = 0;
            VratFarbuPredVztahom(partner);
            new sprava[144];
            format(sprava, sizeof(sprava), "[VZTAH] %s ukoncil(a) vztah s tebou. Farba nicku sa vratila spat.", meno);
            SendClientMessage(partner, 0xFFFF00FF, sprava);
        }
        SendClientMessage(playerid, 0xFFFF00FF, "[VZTAH] Vztah bol ukonceny. Farba nicku sa vratila spat.");
        return 1;
    }

    // ---------- Admin: miesta na rande ----------
    // /randemiesto [nazov] - prida miesto na tvojej pozicii (cerveny kruh sa zobrazi tu)
    if(strcmp("/randemiesto", cmdtext, true, 12) == 0 && (cmdtext[12] == 0 || cmdtext[12] == ' '))
    {
        if(!IsPlayerAdmin(playerid)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento prikaz moze pouzit len admin.");
        new poz = 12, n = 0, nazov[32];
        while(cmdtext[poz] == ' ') poz++;
        while(cmdtext[poz] != 0 && n < 31) nazov[n++] = cmdtext[poz++];
        nazov[n] = 0;
        if(n < 2) return SendClientMessage(playerid, 0xFFFF00FF, "Pouzitie: /randemiesto [nazov miesta]  (postav sa tam, kam maju chodit na rande)");

        new Float:x, Float:y, Float:z;
        GetPlayerPos(playerid, x, y, z);
        new slot = PridajMiesto(nazov, x, y, z, GetPlayerInterior(playerid));
        if(slot == -1) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Dosiahnuty maximalny pocet miest.");
        UlozMiesta();
        new sprava[96];
        format(sprava, sizeof(sprava), "[RANDE] Miesto '%s' bolo pridane a ulozene.", nazov);
        SendClientMessage(playerid, 0x00FF00FF, sprava);
        return 1;
    }

    // /randezmazat - zmaze najblizsie miesto do 5 metrov
    if(strcmp("/randezmazat", cmdtext, true) == 0)
    {
        if(!IsPlayerAdmin(playerid)) return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] Tento prikaz moze pouzit len admin.");
        for(new i = 0; i < MAX_MIEST; i++)
        {
            if(!MiestoAktivne[i]) continue;
            if(GetPlayerInterior(playerid) != MiestoInt[i]) continue;
            if(!IsPlayerInRangeOfPoint(playerid, 5.0, MiestoX[i], MiestoY[i], MiestoZ[i])) continue;
            MiestoAktivne[i] = false;
            UlozMiesta();
            SendClientMessage(playerid, 0x00FF00FF, "[RANDE] Miesto bolo zmazane.");
            return 1;
        }
        return SendClientMessage(playerid, 0xFF0000FF, "[CHYBA] V blizkosti nie je ziadne miesto na rande.");
    }

    return 0; // neznamy prikaz - nech ho spracuje iny skript
}
