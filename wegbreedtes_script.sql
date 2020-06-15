/***************************************************** 
Wegbreedtes uit BGT berekenen m.b.v. wegennetwerk
Generieke versie

Doel: berekenen van de wegbreedtes van de BGT wegvakken op wegen, en eventueel 

- wegennetwerk: lijnentabel met kolom waarin de unieke identifiers (wegvakken zitten). 
- wegvak_kolom: kolom met unieke identifiers voor wegvakken
- test (boolean): true voor testdoeleinden, anders false
- wegvakid (integer): in testmodus kun je hier één wegvak ID meegeven waarvoor het script wordt gedraaid.
  Bij de naam van het wegennetwerk ook het schema meegeven! Voorbeeld: 'public.are_aggr20180227'

Aannamen:
- Wegennetwerk zit in de PostGIS database
- BGT wegdelen zitten in de PostGIS database, tabel "bgt.wegdeel". Voor downloaden van een PostGIS dump, zie: https://data.nlextract.nl

Resultaten:
Het script levert vier tabellen op, in het schema 'breedte_analyse':
1. wegennetwerk: kopie van het invoer wegennetwerk
2. wegvakken_knip: in stukjes geknipte wegvakken: de beginpunten hiervan worden gebruikt om de breedte te berekenen
3. dwarslijntjes_uniek: lijnstukjes vanuit de bij 3) berekende beginpunten, dwars op het wegvak en afgeknipt waar het BGT wegvak ophoudt. De lengte hiervan wordt gebruikt om de wegbreedte te berekenen
4. gemiddeldebreedte: wegvakken uit 1) met breedtegegevens: gemiddelde, maximum, minimum, standaardafwijking, operationele breedte, gemiddelde afstand tot BGT wegvlak, 
   aantal dwarslijntjes en aantal dwarslijntjes na berekenen operationele breedte.
N.B. Alle oorspronkelijke gegevens van het wegennetwerk kun je hier weer aan door middel van een JOIN van dit resultaat met het oorspronkelijke wegennetwerk, op de kolom met wegvak ID. 

Gebruik:
1. Eerst de functie in PostGIS inladen (zie pdf instructie), via de Query Tool, vervolgens bestand ophalen en uitvoeren (F5)
2. Aanroepen via Query Tool: 
SELECT wh_wegbreedte_bgt_generiek('<wegennetwerk>', '<wegvak_kolom>', <testmodus>, 0); 
Voorbeeld:
SELECT wh_wegbreedte_bgt_generiek('nwb.nwb_wegvakken', 'wvk_id', false, 0);

N.B. Laatste 2 argumenten zijn alleen voor testdoeleinden, en zijn voor de gebruiker altijd false, 0. 

Copyright Ruimtemaatwerk, april 2020

+++++++++++++++++++++++++++++++
Wijzigingen:
20200311: nieuwe versie met verbeteringen
          Opbouw zoals landelijke analyse: alle BGT typen in één loopje i.p.v. per wegtype alle wegvakken langs gaan. 
          Alle wegvakken (ook hele korte) worden in 10 geknipt en krijgen 9 lijntjes
          Extra tussenstap 'snappie', om hele kleine gaten tussen (ontcurvede) BGT vlakken te dichten. 
          Extra kolom bij dwarslijntjes_uniek: afwijking (valt buiten STD)
          Extra kolommen bij gemiddeldebreedte: breedte_operationeel, met gecorrigeerd gemiddelde waarbij uitbijters niet meetellen, afstand tot BGT wegvlak, aantal operationele dwarslijntjes.  
          2 extra argumenten: test (boolean) en wegvakid (numeriek). Als test op TRUE staat kun je één wegvak invoeren en worden er een aantal extra dingen bewaard voor testdoeleinden. 
20200427: Nieuwe generieke versie
          Nieuwe functienaam: wh_wegbreedte_bgt_generiek
          wegvak ID komt in onafhankelijke kolom 'wegvakid': die kolom mag dus nog niet bestaan. Kolom met wegvakken moet als argument worden opgegeven

*********************************************************/

DROP FUNCTION IF EXISTS wh_wegbreedte_bgt_generiek;
CREATE FUNCTION wh_wegbreedte_bgt_generiek(wegennetwerk regclass, wegvak_kolom TEXT, test boolean, wegvak INT8) RETURNS text AS 
$$
DECLARE
	--wnetwerk ALIAS FOR $1;
        v_state text;
	v_msg text;
	v_detail text;
	v_hint text;
	v_context text;
	currentlink record;
        tel integer := 1;
        begindeel integer:= 0;
	totaal_aantal integer;
        aantalperkeer integer := 2000; -- performance: hele wegennetwerk analyse opdelen in 'happen' (zie landelijke analyse)
        qqz integer; -- getalletje om dingen te checken
BEGIN
-- initialiseren: extensies, schema e.d.	
IF test THEN RAISE NOTICE 'TESTMODUS!'; END IF;
CREATE SCHEMA IF NOT EXISTS breedte_analyse_nieuw;
RAISE NOTICE 'Wegennetwerk: %', wegennetwerk;


-- Tabellen maken

-------------------------------------------------------
-- wegennetwerk kopie
DROP TABLE IF EXISTS breedte_analyse_nieuw.wegennetwerk;
IF test THEN 
  EXECUTE format('CREATE TABLE breedte_analyse_nieuw.wegennetwerk AS SELECT *, %s AS wegvakid FROM %s WHERE %s = %s;', wegvak_kolom, wegennetwerk, wegvak_kolom, wegvak);
ELSE 
  EXECUTE format ('CREATE TABLE breedte_analyse_nieuw.wegennetwerk AS SELECT *, %s AS wegvakid FROM %s;', wegvak_kolom, wegennetwerk);
END IF;
-- Eventueel nog een selectie doorvoeren. Nu niet nodig.
CREATE INDEX idx_wegennetwerk_wegvakid ON breedte_analyse_nieuw.wegennetwerk USING btree(wegvakid);
CREATE INDEX idx_wegennetwerk_geom ON breedte_analyse_nieuw.wegennetwerk USING gist(geom);
-- Aantal bepalen, teruggeven.
SELECT COUNT(*) FROM breedte_analyse_nieuw.wegennetwerk INTO totaal_aantal;
RAISE NOTICE 'Aantal wegvakken: %', totaal_aantal;

-- wegennetwerk opgeknipt
DROP TABLE IF EXISTS breedte_analyse_nieuw.wegvakken_knip;
CREATE TABLE breedte_analyse_nieuw.wegvakken_knip  
(gid SERIAL PRIMARY KEY,
wegvakid INT8,
geom geometry(Linestring, 28992),
n INTEGER,
lengte numeric(10,2));

CREATE INDEX idx_geoco_wegvakken_knip_geom ON breedte_analyse_nieuw.wegvakken_knip USING gist(geom);
CREATE INDEX idx_geoco_wegvakken_knip_gid ON breedte_analyse_nieuw.wegvakken_knip USING btree(gid);
CREATE INDEX idx_geoco_wegvakken_knip_wegvakid ON breedte_analyse_nieuw.wegvakken_knip USING btree(wegvakid);

-- gemiddeldebreedte
DROP TABLE IF EXISTS breedte_analyse_nieuw.gemiddeldebreedte;
CREATE TABLE breedte_analyse_nieuw.gemiddeldebreedte
(gid SERIAL PRIMARY KEY,
typeweg VARCHAR,
wegvakid INT8,
geom GEOMETRY(Multilinestring,28992),
gem_breedte numeric(10,2),
dev_breedte numeric(10,2),
min_breedte numeric(10,2),
max_breedte numeric(10,2),
oper_breedte numeric(10,2), -- operationele breedte: gemiddelde na verwijderen uitbijters
afst_s numeric(10,2), -- gemiddelde afstand route tot BGT vlak (per wegtype), om te checken welke weg moet als er meerdere BGT wegtypen aan hangen
aantal int2,
aantal_op int2) -- aantal dwarslijntjes na weghalen uitbijters
;

CREATE INDEX idx_gemiddeldebreedte_wegvakid ON breedte_analyse_nieuw.gemiddeldebreedte USING btree(wegvakid);
CREATE INDEX idx_gemiddeldebreedte_gid ON breedte_analyse_nieuw.gemiddeldebreedte USING btree(gid);
CREATE INDEX idx_gemiddeldebreedte_geom ON breedte_analyse_nieuw.gemiddeldebreedte USING gist(geom);

-- dwarslijntjes (tijdelijk)
DROP TABLE IF EXISTS breedte_analyse_nieuw.dwarslijntjes;
CREATE TABLE breedte_analyse_nieuw.dwarslijntjes
(gid SERIAL PRIMARY KEY,
typeweg VARCHAR,
wegvakid INT8,
geom GEOMETRY(MultiLinestring, 28992),
lengte numeric,
dwarslijn_id INTEGER);

CREATE INDEX idx_dwarslijntjes_wegvakid ON breedte_analyse_nieuw.dwarslijntjes USING btree(wegvakid);
CREATE INDEX idx_dwarslijntjes_gid ON breedte_analyse_nieuw.dwarslijntjes USING btree(gid);
CREATE INDEX idx_dwarslijntjes_geom ON breedte_analyse_nieuw.dwarslijntjes USING gist(geom);

-- snappie (tijdelijk)
DROP TABLE IF EXISTS breedte_analyse_nieuw.snappie;
CREATE TABLE breedte_analyse_nieuw.snappie
(gid SERIAL PRIMARY KEY,
typeweg VARCHAR,
wegvakid INT8, 
dwarslijn_id INTEGER,
gidd1 INT8,
geom GEOMETRY(MultiLinestring, 28992),
lengte numeric(8,2),
afstand numeric(8,2),
afstand_s numeric(8,2)
);

CREATE INDEX idx_snappie_wegvakid ON breedte_analyse_nieuw.snappie USING btree(wegvakid);
CREATE INDEX idx_snappie_gid ON breedte_analyse_nieuw.snappie USING btree(gid);
CREATE INDEX idx_snappie_geom ON breedte_analyse_nieuw.snappie USING gist(geom);
CREATE INDEX idx_snappie_dwarslijn_id ON breedte_analyse_nieuw.snappie USING btree(dwarslijn_id);
CREATE INDEX idx_snappie_typeweg ON breedte_analyse_nieuw.snappie USING btree(typeweg);

-- dwarslijntjes_uniek, blijft in eindresultaat
DROP TABLE IF EXISTS breedte_analyse_nieuw.dwarslijntjes_uniek;
CREATE TABLE breedte_analyse_nieuw.dwarslijntjes_uniek
(gid SERIAL PRIMARY KEY,
typeweg VARCHAR, 
wegvakid INT8, 
afstand NUMERIC, 
lengte NUMERIC, 
dwarslijn_id INTEGER, 
afwijking CHAR(1), -- NULL (binnen -1 en +1 STD), H (hoger dan gemiddelde + STD), L (lager dan gemiddelde - STD)
geom GEOMETRY(MultiLinestring, 28992));

CREATE INDEX idx_dwarslijntjes_uniek_wegvakid ON breedte_analyse_nieuw.dwarslijntjes_uniek USING btree(wegvakid);
CREATE INDEX idx_dwarslijntjes_uniek_gid ON breedte_analyse_nieuw.dwarslijntjes_uniek USING btree(gid);
CREATE INDEX idx_dwarslijntjes_uniek_geom ON breedte_analyse_nieuw.dwarslijntjes_uniek USING gist(geom);
CREATE INDEX idx_dwarslijntjes_uniek_afwijking ON breedte_analyse_nieuw.dwarslijntjes_uniek USING btree(afwijking);

------------------------------------------------------------------------------------
-- VANAF HIER EEN LOOP STARTEN: acties over wegennetwerk opdelen in delen. 
RAISE NOTICE 'Procedure wegennetwerk opdelen';
begindeel := 0; -- voor offset: welk deel van het netwerk is aan de beurt
tel := 1;
WHILE begindeel < totaal_aantal 
LOOP
  --EXIT WHEN begindeel > totaal_aantal;
  RAISE NOTICE 'Begin wegvak: %', begindeel;
  -- test hoeveel zit er in dwarslijntjes tabel
  SELECT COUNT(*) FROM breedte_analyse_nieuw.dwarslijntjes INTO qqz;
  -- RAISE NOTICE 'Aantal dwarslijntjes totaal: %', qqz;
  -- Deel wegennetwerk opknippen
  TRUNCATE TABLE breedte_analyse_nieuw.wegvakken_knip;
  INSERT INTO breedte_analyse_nieuw.wegvakken_knip (wegvakid, geom, n, lengte) 
  SELECT wegvakid, geom::geometry(Linestring, 28992), n, lengte
  FROM
  ( 
    SELECT * FROM 
    (
      SELECT wegvakid, ST_LineSubstring(geom, n/10.0, (n+1)/10.0) AS geom, lengte, n
      FROM
      (
        SELECT wegvakid, ST_LineMerge(geom) AS geom, ST_Length(geom) AS lengte
        FROM (SELECT * FROM breedte_analyse_nieuw.wegennetwerk ORDER BY wegvakid LIMIT aantalperkeer OFFSET begindeel) AS deelnetwerk
        -- WHERE ST_Length(geom) > 100
      ) AS t
      CROSS JOIN generate_series(1,9) AS n
    ) AS lang
  ) AS totaal
  ;
  SELECT COUNT(*) FROM breedte_analyse_nieuw.wegvakken_knip INTO qqz;
  -- RAISE NOTICE 'Aantal geknipte wegvakken: %', qqz;

  -----------------------------------------------------------------------------
  -- 2. Dwarslijntjes genereren.
  -- En meteen afknippen
  -- Tabel met dwarslijntjes (niet uniek) leeggooien voor performance.
  TRUNCATE TABLE breedte_analyse_nieuw.dwarslijntjes;                   
  -- Loopje per wegvakid van de wegvakken. 
  --------------------------------------------------------------------------
  FOR currentlink IN 
  SELECT DISTINCT wegvakid
  FROM breedte_analyse_nieuw.wegennetwerk
  ORDER BY wegvakid
  LIMIT aantalperkeer OFFSET begindeel
  LOOP
    BEGIN
    -- RAISE NOTICE 'Verwerken wegvakid %', currentlink.wegvakid;
    -- Per groter aantal (b.v. 1000) wegvakken bijhouden hoe ver ie is.  
    IF (tel % 500 = 0) THEN RAISE NOTICE 'Tel %, Wegvak %', tel, currentlink.wegvakid; END IF;
    INSERT INTO breedte_analyse_nieuw.dwarslijntjes(typeweg, wegvakid, geom, lengte, dwarslijn_id)
    SELECT uu.bgt_functie AS typeweg, currentlink.wegvakid AS wegvakid, ST_Multi(geom)::geometry(MultiLinestring, 28992) AS geom, ST_Length(geom)::numeric(6,2) AS lengte, gid AS dwarslijn_id
    FROM
    (
      -- Dwarslijntjes afknippen op intersection met BGT vlakken. ST_LineMerge(ST_Union) is nodig vanwege procedure bij 'snappie'				
      SELECT l.gid, u.bgt_functie, (ST_Dump(ST_LineMerge(ST_Union(ST_Intersection(l.geom, u.geom))))).geom AS geom
      FROM
      (
        -- Dwarslijntjes maken: max. breedte vastzetten op 15 (wellicht groter maken?)				
        SELECT gid, geo, hoek, ST_SetSRID(ST_Rotate(ST_MakeLine(ST_MakePoint(ST_X(geom) - 15,ST_Y(geom)), ST_MakePoint(ST_X(geom) + 15,ST_Y(geom))),-hoek, geom), 28992) AS geom
        FROM 
        (
          -- Startpunt lijnstukjes: middelpunt van dwarslijntjes							
          SELECT gid, ST_SetSRID(ST_Startpoint(geom), 28992) AS geom, 
          ST_AsText(ST_Startpoint(geom)) AS geo, ST_Azimuth(ST_LineInterpolatePoint(geom, 0), ST_LineInterpolatePoint(geom, 0.1)) AS hoek
          FROM breedte_analyse_nieuw.wegvakken_knip WHERE wegvakid = currentlink.wegvakid
        ) AS puntjes
      ) AS l
      JOIN 
      (
        -- BGT wegdelen selecteren binnen 10m van lijnstukje. Selectie uit BGT welke bgt_functie
        -- Als je fietspaden grenzend aan rijbanen wil meetellen in de breedte moet je hier BGT functies samenvoegen
        SELECT DISTINCT b.bgt_functie, ST_Buffer(b.geometrie_vlak,0,999) AS geom 
        --SELECT b.bgt_functie, ST_Union(geometrie_vlak) AS geom 
        FROM bgt.wegdeel AS b 
        JOIN (SELECT ST_Buffer(geom,10,2) AS geom FROM breedte_analyse_nieuw.wegvakken_knip WHERE wegvakid = currentlink.wegvakid) AS g 
        ON b.geometrie_vlak && g.geom 
        WHERE (b.bgt_functie IN ('fietspad', 'OV-baan') OR b.bgt_functie ILIKE 'rijbaan%') -- Eventueel ook IsValid geometrie
        -- GROUP BY b.bgt_functie
      ) AS u
      ON ST_Intersects(l.geom, u.geom)
      GROUP BY gid, bgt_functie
    ) AS uu
    ;
    EXCEPTION
    WHEN OTHERS THEN 
    GET STACKED DIAGNOSTICS
    v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT;
    raise notice E'Got exception: 
    state  : %
    message: %
    detail : %
    hint   : %', v_state, v_msg, v_detail, v_hint;
    RAISE NOTICE 'Foutje in wegvakid %', currentlink.wegvakid;
    END;
    tel := tel + 1;
  END LOOP;


  -- Tussenstap: tabel met gegevens over dwarslijntjes, hier wordt op basis van onderlinge afstand en afstand tot de routelijn (afstand_s) bepaald welke relevant zijn
  TRUNCATE TABLE breedte_analyse_nieuw.snappie;
  INSERT INTO breedte_analyse_nieuw.snappie (typeweg, wegvakid, dwarslijn_id, gidd1, geom, lengte, afstand, afstand_s)
  SELECT d1.typeweg, d1.wegvakid, d1.dwarslijn_id, d1.gid, d1.geom, d1.lengte, MIN(ST_Distance(d1.geom, d2.geom)) AS afstand, MIN(ST_Distance(d1.geom, s.geom)) AS afstand_s
  FROM breedte_analyse_nieuw.dwarslijntjes AS d1
  JOIN breedte_analyse_nieuw.dwarslijntjes AS d2
  ON d1.dwarslijn_id = d2.dwarslijn_id AND d1.wegvakid = d2.wegvakid AND d1.typeweg = d2.typeweg
  JOIN breedte_analyse_nieuw.wegvakken_knip AS s
  ON d1.wegvakid = s.wegvakid
  JOIN (SELECT typeweg, wegvakid, dwarslijn_id, COUNT(*) AS aantal FROM breedte_analyse_nieuw.dwarslijntjes GROUP BY typeweg, wegvakid, dwarslijn_id) AS aantaldwars
  ON d1.wegvakid = aantaldwars.wegvakid AND d1.dwarslijn_id = aantaldwars.dwarslijn_id AND d1.typeweg = aantaldwars.typeweg
  WHERE d1.gid != d2.gid OR aantaldwars.aantal = 1
  GROUP BY d1.typeweg, d1.wegvakid, d1.dwarslijn_id, d1.geom, d1.lengte, d1.gid
  ORDER BY dwarslijn_id, afstand_s, afstand;  
  SELECT COUNT(*) FROM breedte_analyse_nieuw.snappie INTO qqz;
  -- RAISE NOTICE 'Snappie aantal: %', qqz;


-- Niet relevante lijnstukjes wegmikken (onderlinge afstand > 10 cm EN afstand_s is groter dan minimum).
-- Ook rekening houden met verschillend wegtype? 
-- Zo niet, dan wordt 'dubbel fietspad' aan beide kanten weggemikt. 

  IF NOT test THEN
    DELETE FROM breedte_analyse_nieuw.snappie AS s
    USING (SELECT dwarslijn_id, wegvakid, MIN(afstand_s) AS a_min FROM breedte_analyse_nieuw.snappie GROUP BY dwarslijn_id, wegvakid) AS sg
    WHERE s.wegvakid = sg.wegvakid AND s.dwarslijn_id = sg.dwarslijn_id AND s.afstand_s > sg.a_min AND s.afstand > 0.10; 
    SELECT COUNT(*) FROM breedte_analyse_nieuw.snappie INTO qqz;
  -- RAISE NOTICE 'Snappie aantal na delete: %', qqz;
  END IF;

  -- 3. Tabel met unieke dwarslijntjes (samengevoegd per dwarslijn_id / typeweg), met info over afstand tot route en totale lengte. 
  -- Eventueel aanpassen: ander selectiekriterium
  INSERT INTO breedte_analyse_nieuw.dwarslijntjes_uniek(typeweg, wegvakid, dwarslijn_id, afstand, lengte, geom)
  SELECT 
    typeweg, wegvakid, dwarslijn_id, MIN(afstand_s), SUM(lengte), ST_CollectionExtract(ST_Collect(geom),2)
  FROM breedte_analyse_nieuw.snappie AS d
  GROUP BY typeweg, wegvakid, dwarslijn_id
  ;
  
  SELECT COUNT(*) FROM breedte_analyse_nieuw.dwarslijntjes_uniek INTO qqz;
  RAISE NOTICE 'Aantal dwarslijntjes totaal: %', qqz;
  begindeel := begindeel + aantalperkeer;
END LOOP; -- Loop wegennetwerk opdelen

----------------------------------------------------------------------------
-- 4. Tabel met gemiddelde breedte vullen. Bij meerdere breedtes(wegtypen) per wegvak meteen de dichtstbije kiezen en de andere wegmikken? B.v. fietspad langs weg, fietspad moet eruit. 
INSERT INTO breedte_analyse_nieuw.gemiddeldebreedte (typeweg, wegvakid, geom, gem_breedte, dev_breedte, min_breedte, max_breedte, aantal, afst_s)
SELECT DISTINCT ON (wegvakid)
  typeweg, wegvakid, geom, gem_breedte, dev_breedte, min_breedte, max_breedte, aantal, afst_s 
FROM 
(
  SELECT
    d.typeweg, k.wegvakid, k.geom, AVG(d.lengte)::numeric(6,2) AS gem_breedte, STDDEV(d.lengte)::numeric(6,2) AS dev_breedte, MIN(d.lengte)::numeric(6,2) AS min_breedte, MAX(d.lengte)::numeric(6,2) AS max_breedte, COUNT(*) AS aantal,  AVG(afstand) AS afst_s
  FROM breedte_analyse_nieuw.dwarslijntjes_uniek AS d
  JOIN breedte_analyse_nieuw.wegennetwerk AS k
  ON d.wegvakid = k.wegvakid
  GROUP BY d.typeweg, k.wegvakid, k.geom
  ORDER BY wegvakid, aantal DESC, afst_s -- Aantal dwarslijntjes of afstand? Als het echt goed gedigitaliseerd is, is afstand wellicht beter, maar dat is het niet.
) AS alles
;

----------------------------------------------------------------------------
-- Naselectie
-- Dwarslijntjes met te grote afwijking van gemiddelde (+ of - STD)
UPDATE breedte_analyse_nieuw.dwarslijntjes_uniek AS d
SET afwijking = CASE WHEN d.lengte < (g.gem_breedte - g.dev_breedte) THEN 'L' WHEN d.lengte > (g.gem_breedte + g.dev_breedte) THEN 'H' END
FROM breedte_analyse_nieuw.gemiddeldebreedte AS g
WHERE d.typeweg = g.typeweg AND d.wegvakid = g.wegvakid; 

-- Operationele breedte berekenen: na weglaten dwarslijntjes met te grote afwijking
UPDATE breedte_analyse_nieuw.gemiddeldebreedte AS g
SET oper_breedte = d.lengte, aantal_op = d.aantal
FROM 
(
  SELECT wegvakid, typeweg, AVG(lengte) AS lengte, COUNT(*) AS aantal
  FROM breedte_analyse_nieuw.dwarslijntjes_uniek
  WHERE afwijking IS NULL
  GROUP BY wegvakid, typeweg
) AS d
WHERE d.typeweg = g.typeweg AND d.wegvakid = g.wegvakid;

-- Opruimen overbodige tabellen
IF NOT test 
THEN 
  DROP TABLE breedte_analyse_nieuw.dwarslijntjes;
  DROP TABLE breedte_analyse_nieuw.snappie;
END IF;

RETURN 'OK!';

-- Als het fout is gegaan ergens:
EXCEPTION
	WHEN OTHERS THEN 
    GET STACKED DIAGNOSTICS
	v_state   = RETURNED_SQLSTATE,
	v_msg     = MESSAGE_TEXT,
	v_detail  = PG_EXCEPTION_DETAIL,
	v_hint    = PG_EXCEPTION_HINT;
	raise notice E'Got exception:
	state  : %
	message: %
	detail : %
	hint   : %', v_state, v_msg, v_detail, v_hint;
	RAISE NOTICE 'Foutje!';
	RETURN 'Foutje!';

END;
$$ LANGUAGE plpgsql;






