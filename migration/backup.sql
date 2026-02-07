--
-- PostgreSQL database dump
--

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg12+2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-1.pgdg12+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: nbfodb_user
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO nbfodb_user;

--
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: nbfodb_user
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";


--
-- Name: EXTENSION "pgcrypto"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "pgcrypto" IS 'cryptographic functions';


--
-- Name: check_destruction_role(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."check_destruction_role"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.type_retrait = 'destruction' THEN
    -- VÃ©rifier rÃ´le de lâ€™utilisateur
    IF NOT EXISTS (
      SELECT 1 FROM utilisateurs u
      WHERE u.nom = NEW.utilisateur
      AND u.role IN ('admin','superadmin')
    ) THEN
      RAISE EXCEPTION 'Seuls (super)admins peuvent enregistrer un retrait de type destruction';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_destruction_role"() OWNER TO nbfodb_user;

--
-- Name: fn_execute_transfert_valide(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."fn_execute_transfert_valide"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Si l'audit passe … TRUE, on effectue le mouvement physique
    IF (NEW.audit_final_ok = TRUE AND OLD.audit_final_ok = FALSE) THEN
        -- 1. D‚duction au d‚part
        UPDATE stocks SET quantite = quantite - NEW.quantite 
        WHERE magasin_id = NEW.magasin_id_depart AND lot_id = NEW.lot_id;
        
        -- 2. Ajout (ou cr‚ation) … la destination
        INSERT INTO stocks (magasin_id, lot_id, quantite)
        VALUES (NEW.magasin_id_dest, NEW.lot_id, NEW.quantite)
        ON CONFLICT (magasin_id, lot_id) 
        DO UPDATE SET quantite = stocks.quantite + NEW.quantite;

        NEW.statut := 'APPROVED';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_execute_transfert_valide"() OWNER TO nbfodb_user;

--
-- Name: fn_finaliser_transfert(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."fn_finaliser_transfert"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Si l'auditeur vient de donner son accord (audit_final_ok passe … TRUE)
    IF (TG_OP = 'UPDATE' AND NEW.audit_final_ok = TRUE AND OLD.audit_final_ok = FALSE) THEN
        
        -- 1. Retirer du magasin de d‚part
        UPDATE stock 
        SET quantite = quantite - NEW.quantite 
        WHERE magasin_id = NEW.magasin_id_depart AND lot_id = NEW.lot_id;

        -- 2. Ajouter au magasin de destination
        -- (Ou cr‚er la ligne si elle n'existe pas)
        INSERT INTO stock (magasin_id, lot_id, quantite)
        VALUES (NEW.magasin_id_dest, NEW.lot_id, NEW.quantite)
        ON CONFLICT (magasin_id, lot_id) 
        DO UPDATE SET quantite = stock.quantite + NEW.quantite;

        -- 3. Mettre … jour le statut
        NEW.statut := 'APPROVED_BY_AUDIT';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_finaliser_transfert"() OWNER TO nbfodb_user;

--
-- Name: generate_employer_id(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."generate_employer_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  magasin_code VARCHAR(10);
  seq_num INT;
BEGIN
  SELECT code INTO magasin_code FROM magasins WHERE id = NEW.magasin_id;

  SELECT COUNT(*)+1 INTO seq_num
  FROM employers WHERE magasin_id = NEW.magasin_id AND role = NEW.role;

  NEW.id := magasin_code || '_' || NEW.role || '_' || LPAD(seq_num::text, 3, '0');

  NEW.matricule := NEW.role || '_' ||
                   TO_CHAR(NOW(), 'MM-YYYY') || '_' ||
                   LPAD(seq_num::text, 3, '0');

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_employer_id"() OWNER TO nbfodb_user;

--
-- Name: generate_producteur_id(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."generate_producteur_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  arr_code TEXT;
  seq_num INT;
  type_prefix TEXT;
BEGIN
  -- RÃ©cupÃ©rer le code de lâ€™arrondissement (ex: NYK_001)
  SELECT code INTO arr_code
  FROM arrondissements
  WHERE id = NEW.arrondissement_id;

  -- NumÃ©ro dâ€™ordre : combien de producteurs de ce type dans cet arrondissement
  SELECT COUNT(*)+1 INTO seq_num
  FROM producteurs
  WHERE arrondissement_id = NEW.arrondissement_id
    AND type_producteur = NEW.type_producteur;

  -- PrÃ©fixe basÃ© sur type_producteur
  CASE NEW.type_producteur
    WHEN 'agriculteur' THEN type_prefix := 'agri';
    WHEN 'Ã©leveur' THEN type_prefix := 'eleveur';
    WHEN 'pÃªcheur' THEN type_prefix := 'pecheur';
    WHEN 'artisan' THEN type_prefix := 'artisan';
    WHEN 'alimentaire manufacture' THEN type_prefix := 'alim';
    WHEN 'coopÃ©rative' THEN type_prefix := 'coop';
    WHEN 'individuel' THEN type_prefix := 'indiv';
    ELSE type_prefix := 'autre';
  END CASE;

  -- GÃ©nÃ©rer le matricule (lisible, basÃ© sur type + date + numÃ©ro)
  NEW.matricule := type_prefix || '_' ||
                   TO_CHAR(COALESCE(NEW.date_integration, CURRENT_DATE), 'MM-YYYY') || '_' ||
                   LPAD(seq_num::text, 3, '0');

  -- NB : lâ€™ID reste SERIAL (integer), on ne le modifie pas
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_producteur_id"() OWNER TO nbfodb_user;

--
-- Name: generate_user_id(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."generate_user_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  magasin_code VARCHAR(10);
  seq_num INT;
BEGIN
  -- 1. R‚cup‚rer le code du magasin (si applicable)
  IF NEW.magasin_id IS NOT NULL THEN
      SELECT code INTO magasin_code FROM magasins WHERE id = NEW.magasin_id;
  ELSE
      magasin_code := 'SYS';
  END IF;

  -- 2. Calcul du num‚ro d'ordre
  SELECT COUNT(*) + 1 INTO seq_num
  FROM users 
  WHERE (magasin_id = NEW.magasin_id OR (magasin_id IS NULL AND NEW.magasin_id IS NULL))
    AND role = NEW.role;

  -- 3. G‚n‚ration de l'ID et du Matricule
  -- On utilise COALESCE pour ‚viter les ID vides si magasin_code est manquant
  NEW.id := COALESCE(magasin_code, 'EXT') || '_' || NEW.role || '_' || LPAD(seq_num::text, 3, '0');
  
  NEW.matricule := UPPER(LEFT(NEW.role, 3)) || '_' || 
                   TO_CHAR(NOW(), 'MM-YYYY') || '_' || 
                   LPAD(seq_num::text, 3, '0');

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_user_id"() OWNER TO nbfodb_user;

--
-- Name: handle_magasin_transfer(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."handle_magasin_transfer"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.type_retrait = 'magasin' AND NEW.destination_magasin_id IS NOT NULL THEN
    INSERT INTO admissions (
      lot_id,
      producteur_id,
      utilisateur,
      quantite,
      unite,
      prix_ref,
      valeur_totale,
      date_reception,  -- ← CHANGÉ de date_admission à date_reception
      magasin_id,
      coef_qualite,
      taux_tax,
      region_id,
      departement_id,
      arrondissement_id,
      localite
    )
    VALUES (
      NEW.lot_id,
      363,  -- Pas de producteur pour un transfert
      NEW.utilisateur,
      NEW.quantite,
      NEW.unite,
      NEW.prix_ref,
      NEW.valeur_totale,
      CURRENT_DATE,  -- ← Date de réception = aujourd'hui
      NEW.destination_magasin_id,
      NEW.coef_qualite,
      NEW.taux_tax,
      NEW.region_id,
      NEW.departement_id,
      NEW.arrondissement_id,
      NEW.localite
    );
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_magasin_transfer"() OWNER TO nbfodb_user;

--
-- Name: nbfo_get_quality_coef(character); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_get_quality_coef"("q" character) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN CASE 
        WHEN grade_qualite = 'A' THEN 1.0 
        WHEN grade_qualite = 'B' THEN 0.90 
        WHEN grade_qualite = 'C' THEN 0.80 
        WHEN grade_qualite = 'D' THEN 0.70 
        ELSE 0.5 
    END;
END;
$$;


ALTER FUNCTION "public"."nbfo_get_quality_coef"("q" character) OWNER TO nbfodb_user;

--
-- Name: nbfo_get_tax_rate(character varying); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_get_tax_rate"("p_categorie" character varying) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN CASE 
        WHEN p_categorie = 'frais'             THEN 0.05
        WHEN p_categorie = 'secs'              THEN 0.03
        WHEN p_categorie = 'huiles_liquides'   THEN 0.04
        WHEN p_categorie = 'produits_foret'    THEN 0.06
        WHEN p_categorie = 'sensibles'         THEN 0.08
        ELSE 0.05
    END;
END;
$$;


ALTER FUNCTION "public"."nbfo_get_tax_rate"("p_categorie" character varying) OWNER TO nbfodb_user;

--
-- Name: nbfo_lot_remaining(integer); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_lot_remaining"("p_lot_id" integer) RETURNS numeric
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  total_entree NUMERIC := 0;
  total_sortie NUMERIC := 0;
BEGIN
  SELECT COALESCE(SUM(quantite),0) INTO total_entree FROM lots WHERE lot_id = p_lot_id AND type_mouvement = 'entree';
  SELECT COALESCE(SUM(quantite),0) INTO total_sortie FROM lots WHERE lot_id = p_lot_id AND type_mouvement = 'sortie';
  RETURN total_entree - total_sortie;
END;
$$;


ALTER FUNCTION "public"."nbfo_lot_remaining"("p_lot_id" integer) OWNER TO nbfodb_user;

--
-- Name: nbfo_on_admission_insert(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_on_admission_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_estimee NUMERIC(18,2);
    v_tax_rate NUMERIC(5,4);
    v_tax_amount NUMERIC(18,2);
    v_coef_qualite NUMERIC(6,4);
    v_grade CHAR(1);
BEGIN
    v_coef_qualite := COALESCE(NEW.coef_qualite, 1.0);

    -- Grade
    v_grade := CASE
        WHEN v_coef_qualite >= 1.0 THEN 'A'
        WHEN v_coef_qualite >= 0.9 THEN 'B'
        WHEN v_coef_qualite >= 0.8 THEN 'C'
        ELSE 'D'
    END;

    -- Taxe de base
    v_tax_rate := 0.05;
    IF NEW.mode_paiement = 'mobile_money' THEN
        v_tax_rate := v_tax_rate + 0.02;
    END IF;

    -- Pénalité fraîcheur
    IF NEW.date_expiration IS NOT NULL THEN
        DECLARE
            jours_restants INTEGER := NEW.date_expiration - NEW.date_reception;
        BEGIN
            IF jours_restants < 30 THEN
                v_tax_rate := v_tax_rate + (0.005 * (30 - GREATEST(jours_restants, 0)));
            END IF;
        END;
    END IF;

    -- Calculs finaux
    v_estimee := NEW.quantite * NEW.prix_ref * v_coef_qualite;
    v_tax_amount := v_estimee * v_tax_rate;

    -- 1. On affecte directement les colonnes de NEW (plus besoin d'UPDATE admissions)
    NEW.valeur_totale := v_estimee;
    NEW.benefice_estime := v_tax_amount;
    NEW.montant_verse := v_estimee - v_tax_amount;
    NEW.taux_tax := v_tax_rate;
    NEW.grade_qualite := v_grade;

    -- 2. Mise à jour du solde du producteur (Le crédit effectif)
    UPDATE producteurs 
    SET solde = solde + (v_estimee - v_tax_amount)
    WHERE id = NEW.producteur_id;

    -- 3. Insertion dans virtual_revenues
    INSERT INTO virtual_revenues (
        admission_id, lot_id, quantite, prix_ref, qual, coef_qualite, 
        estimee, tax_rate, tax_amount, status, quantite_restante, 
        benefice_espere, net_amount
    ) VALUES (
        NEW.id, NEW.lot_id, NEW.quantite, NEW.prix_ref, v_grade, v_coef_qualite,
        v_estimee, v_tax_rate, v_tax_amount, 'pending', NEW.quantite, 
        v_tax_amount, (v_estimee - v_tax_amount)
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."nbfo_on_admission_insert"() OWNER TO nbfodb_user;

--
-- Name: nbfo_on_lots_change(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_on_lots_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- On v‚rifie NEW.id (l'ID du lot lui-mˆme) et non NEW.lot_id
  IF NEW.id IS NULL THEN 
    -- Si c'est un SERIAL, l'ID est g‚n‚r‚ ici, donc il ne devrait jamais ˆtre nul
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."nbfo_on_lots_change"() OWNER TO nbfodb_user;

--
-- Name: nbfo_on_retrait_insert(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_on_retrait_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_profit_unitaire NUMERIC;
    v_tax_realisee NUMERIC;
    v_date_exp TIMESTAMP;
    v_jours_restants INTEGER;
    v_gain_fraicheur NUMERIC := 0;
    v_prix_acquisition_unit NUMERIC;
BEGIN
    -- 1. R‚cup‚rer les infos de l'admission via la caisse virtuelle
    SELECT 
        vr.profit_unitaire_virtuel, 
        a.date_expiration,
        a.prix_ref
    INTO 
        v_profit_unitaire, 
        v_date_exp,
        v_prix_acquisition_unit
    FROM virtual_revenues vr
    JOIN admissions a ON vr.admission_id = a.id
    WHERE vr.admission_id = NEW.admission_id;

    -- 2. Calcul du Profit de Taxe R‚alis‚
    v_tax_realisee := ROUND(NEW.quantite * v_profit_unitaire, 2);

    -- 3. Calcul du Gain de FraŒcheur (Bonus de performance)
    -- On compare la date de sortie au d‚lai d'expiration
    v_jours_restants := EXTRACT(DAY FROM (v_date_exp - NEW.date_sortie));
    
    IF v_jours_restants > 0 AND NEW.type_retrait = 'client' THEN
        -- Bonus : 0.2% de la valeur d'acquisition par jour restant
        v_gain_fraicheur := ROUND((NEW.quantite * v_prix_acquisition_unit) * (v_jours_restants * 0.002), 2);
    END IF;

    -- 4. Inscription dans la BANQUE INTERNE (Pour les Auditeurs)
    INSERT INTO internal_bank_logs (
        type_mouvement,
        lot_id,
        admission_id,
        montant_realise,    -- Taxe pr‚lev‚e
        difference_valeur,  -- Gain de fraŒcheur
        utilisateur,
        prix_acquisition_total,
        prix_sortie_total
    ) VALUES (
        'RETRAIT_' || UPPER(NEW.type_retrait),
        NEW.lot_id,
        NEW.admission_id,
        CASE WHEN NEW.type_retrait = 'destruction' THEN 0 ELSE v_tax_realisee END,
        CASE WHEN NEW.type_retrait = 'destruction' THEN -(NEW.quantite * v_prix_acquisition_unit) ELSE v_gain_fraicheur END,
        NEW.utilisateur,
        (NEW.quantite * v_prix_acquisition_unit),
        NEW.valeur_totale
    );

    -- 5. Mise … jour de la Caisse Virtuelle
    UPDATE virtual_revenues 
    SET quantite_restante = COALESCE(quantite_restante, quantite) - NEW.quantite,
        status = CASE WHEN (COALESCE(quantite_restante, quantite) - NEW.quantite) <= 0 THEN 'realized' ELSE 'pending' END
    WHERE admission_id = NEW.admission_id;

    -- 6. Mise … jour du stock physique (Table lots)
    UPDATE lots 
    SET stock_disponible = stock_disponible - NEW.quantite
    WHERE id = NEW.lot_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."nbfo_on_retrait_insert"() OWNER TO nbfodb_user;

--
-- Name: nbfo_realize_lot(integer); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."nbfo_realize_lot"("p_lot_id" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  vr RECORD;
BEGIN
  -- rÃ©cupÃ©rer la recette virtuelle en attente
  SELECT * INTO vr 
  FROM virtual_revenues 
  WHERE lot_id = p_lot_id AND status = 'pending' 
  ORDER BY created_at LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE 'Aucune recette virtuelle pending pour le lot %', p_lot_id;
    RETURN;
  END IF;

  -- insÃ©rer dans realized_gains avec brut, taxe et net
  INSERT INTO realized_gains (
    lot_id, virtual_revenue_id, gross_amount, tax_amount, net_amount, amount, details
  ) VALUES (
    p_lot_id, vr.id, vr.estimee, vr.tax_amount, vr.net_amount, vr.net_amount,
    'RÃ©alisation automatique / manuelle'
  );

  -- mettre Ã  jour la recette virtuelle
  UPDATE virtual_revenues
    SET status = 'realized', realized_at = CURRENT_TIMESTAMP
    WHERE id = vr.id;

  RAISE NOTICE 'Lot % rÃ©alisÃ© : Brut=% FCFA, Taxe=% FCFA, Net=% FCFA',
    p_lot_id, vr.estimee, vr.tax_amount, vr.net_amount;
END;
$$;


ALTER FUNCTION "public"."nbfo_realize_lot"("p_lot_id" integer) OWNER TO nbfodb_user;

--
-- Name: trg_decrementer_solde_producteur(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."trg_decrementer_solde_producteur"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- On vérifie que c'est bien une sortie d'argent pour un producteur
    IF NEW.type_operation = 'debit' AND NEW.producteur_id IS NOT NULL THEN
        
        -- On vérifie si le solde est suffisant (sécurité doublant la contrainte CHECK)
        IF (SELECT solde FROM producteurs WHERE id = NEW.producteur_id) < NEW.montant THEN
            RAISE EXCEPTION 'Solde insuffisant pour ce producteur.';
        END IF;

        UPDATE producteurs 
        SET solde = solde - NEW.montant
        WHERE id = NEW.producteur_id;
        
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_decrementer_solde_producteur"() OWNER TO nbfodb_user;

--
-- Name: update_stock_on_retrait(); Type: FUNCTION; Schema: public; Owner: nbfodb_user
--

CREATE FUNCTION "public"."update_stock_on_retrait"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  stock_disponible NUMERIC;
BEGIN
  -- Calculer le stock manuellement (sans vue, directement dans le trigger)
  SELECT 
    COALESCE(SUM(a.quantite), 0) - COALESCE(
      (SELECT SUM(r.quantite) 
       FROM retraits r 
       WHERE r.lot_id = NEW.lot_id 
         AND r.magasin_id = NEW.magasin_id
      ), 0
    )
  INTO stock_disponible
  FROM admissions a
  WHERE a.lot_id = NEW.lot_id 
    AND a.magasin_id = NEW.magasin_id;

  -- V‚rifier
  IF stock_disponible IS NULL OR stock_disponible = 0 THEN
    RAISE EXCEPTION 'Aucun stock disponible pour le lot % au magasin %', 
      NEW.lot_id, NEW.magasin_id;
  END IF;

  IF stock_disponible < NEW.quantite THEN
    RAISE EXCEPTION 'Stock insuffisant pour le lot % au magasin %. Disponible: % kg, Demand‚: % %',
      NEW.lot_id, NEW.magasin_id, stock_disponible, NEW.quantite, NEW.unite;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_stock_on_retrait"() OWNER TO nbfodb_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admissions; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."admissions" (
    "id" integer NOT NULL,
    "lot_id" integer NOT NULL,
    "producteur_id" integer NOT NULL,
    "quantite" numeric(12,2) NOT NULL,
    "unite" character varying(20) NOT NULL,
    "prix_ref" numeric(12,2) NOT NULL,
    "date_reception" "date" NOT NULL,
    "date_expiration" "date",
    "magasin_id" integer NOT NULL,
    "utilisateur" character varying(50) NOT NULL,
    "valeur_totale" numeric(12,2),
    "benefice_estime" numeric(12,2),
    "coef_qualite" numeric(4,2),
    "taux_tax" numeric(4,2),
    "region_id" integer,
    "departement_id" integer,
    "arrondissement_id" integer,
    "localite" character varying(100),
    "mode_paiement" character varying(20) DEFAULT 'solde'::character varying,
    "montant_verse" numeric(15,2),
    "grade_qualite" character varying(10),
    "user_id" integer,
    CONSTRAINT "admissions_mode_paiement_check" CHECK ((("mode_paiement")::"text" = ANY ((ARRAY['solde'::character varying, 'mobile_money'::character varying])::"text"[])))
);


ALTER TABLE public.admissions OWNER TO nbfodb_user;

--
-- Name: admissions_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."admissions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.admissions_id_seq OWNER TO nbfodb_user;

--
-- Name: admissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."admissions_id_seq" OWNED BY "public"."admissions"."id";


--
-- Name: arrondissements; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."arrondissements" (
    "id" integer NOT NULL,
    "nom" character varying(100) NOT NULL,
    "departement_id" integer NOT NULL,
    "code" character varying(50)
);


ALTER TABLE public.arrondissements OWNER TO nbfodb_user;

--
-- Name: arrondissements_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."arrondissements_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.arrondissements_id_seq OWNER TO nbfodb_user;

--
-- Name: arrondissements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."arrondissements_id_seq" OWNED BY "public"."arrondissements"."id";


--
-- Name: audit; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."audit" (
    "id" integer NOT NULL,
    "date" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "utilisateur" character varying(50) NOT NULL,
    "action" "text" NOT NULL
);


ALTER TABLE public.audit OWNER TO nbfodb_user;

--
-- Name: audit_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."audit_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_id_seq OWNER TO nbfodb_user;

--
-- Name: audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."audit_id_seq" OWNED BY "public"."audit"."id";


--
-- Name: caisse; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."caisse" (
    "id" integer NOT NULL,
    "benefices_virtuels" numeric(12,2) DEFAULT 0
);


ALTER TABLE public.caisse OWNER TO nbfodb_user;

--
-- Name: caisse_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."caisse_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.caisse_id_seq OWNER TO nbfodb_user;

--
-- Name: caisse_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."caisse_id_seq" OWNED BY "public"."caisse"."id";


--
-- Name: caisse_lignes; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."caisse_lignes" (
    "id" integer NOT NULL,
    "caisse_id" integer,
    "lot_id" integer,
    "producteur_id" integer,
    "type_operation" character varying(50),
    "montant" numeric(12,2),
    "statut" character varying(20),
    "reference" "jsonb"
);


ALTER TABLE public.caisse_lignes OWNER TO nbfodb_user;

--
-- Name: caisse_lignes_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."caisse_lignes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.caisse_lignes_id_seq OWNER TO nbfodb_user;

--
-- Name: caisse_lignes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."caisse_lignes_id_seq" OWNED BY "public"."caisse_lignes"."id";


--
-- Name: cheques; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."cheques" (
    "id" integer NOT NULL,
    "numero_cheque" character varying(50) NOT NULL,
    "banque" character varying(100) NOT NULL,
    "montant" numeric(12,2) NOT NULL,
    "emetteur" character varying(100) NOT NULL,
    "date_enregistrement" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.cheques OWNER TO nbfodb_user;

--
-- Name: cheques_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."cheques_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cheques_id_seq OWNER TO nbfodb_user;

--
-- Name: cheques_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."cheques_id_seq" OWNED BY "public"."cheques"."id";


--
-- Name: departement_codes; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."departement_codes" (
    "departement_id" integer NOT NULL,
    "code" character varying(10) NOT NULL
);


ALTER TABLE public.departement_codes OWNER TO nbfodb_user;

--
-- Name: departements; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."departements" (
    "id" integer NOT NULL,
    "nom" character varying(100) NOT NULL,
    "region_id" integer NOT NULL
);


ALTER TABLE public.departements OWNER TO nbfodb_user;

--
-- Name: departements_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."departements_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departements_id_seq OWNER TO nbfodb_user;

--
-- Name: departements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."departements_id_seq" OWNED BY "public"."departements"."id";


--
-- Name: employers; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."employers" (
    "id" character varying(50) NOT NULL,
    "magasin_id" integer,
    "nom" character varying(100) NOT NULL,
    "role" character varying(50) NOT NULL,
    "contact" character varying(50),
    "date_embauche" "date",
    "statut" character varying(20) DEFAULT 'actif'::character varying,
    "matricule" character varying(50),
    CONSTRAINT "employers_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['manutentionnaire'::character varying, 'securite'::character varying, 'chauffeur'::character varying, 'caissier'::character varying, 'magasinier'::character varying, 'maintenance'::character varying, 'nettoyage'::character varying, 'logistique'::character varying])::"text"[])))
);


ALTER TABLE public.employers OWNER TO nbfodb_user;

--
-- Name: employers_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."employers_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employers_id_seq OWNER TO nbfodb_user;

--
-- Name: employers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."employers_id_seq" OWNED BY "public"."employers"."id";


--
-- Name: internal_bank_logs; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."internal_bank_logs" (
    "id" integer NOT NULL,
    "type_mouvement" character varying(50) DEFAULT 'REALISATION_PROFIT'::character varying,
    "lot_id" integer,
    "admission_id" integer,
    "montant_realise" numeric(15,2),
    "prix_acquisition_total" numeric(15,2),
    "prix_sortie_total" numeric(15,2),
    "difference_valeur" numeric(15,2),
    "date_operation" timestamp without time zone DEFAULT "now"(),
    "utilisateur" character varying(50)
);


ALTER TABLE public.internal_bank_logs OWNER TO nbfodb_user;

--
-- Name: internal_bank_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."internal_bank_logs_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.internal_bank_logs_id_seq OWNER TO nbfodb_user;

--
-- Name: internal_bank_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."internal_bank_logs_id_seq" OWNED BY "public"."internal_bank_logs"."id";


--
-- Name: logs_deploiement; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."logs_deploiement" (
    "id" integer NOT NULL,
    "date_erreur" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "contexte" character varying(100),
    "utilisateur" character varying(100),
    "role_utilisateur" character varying(50),
    "message_erreur" "text",
    "etat_formulaire" "jsonb",
    "resolu" boolean DEFAULT false
);


ALTER TABLE public.logs_deploiement OWNER TO nbfodb_user;

--
-- Name: logs_deploiement_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."logs_deploiement_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.logs_deploiement_id_seq OWNER TO nbfodb_user;

--
-- Name: logs_deploiement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."logs_deploiement_id_seq" OWNED BY "public"."logs_deploiement"."id";


--
-- Name: lots; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."lots" (
    "id" integer NOT NULL,
    "description" character varying(255) NOT NULL,
    "categorie" character varying(100) NOT NULL,
    "date_creation" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "criteres_admission" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "unites_admises" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "prix_ref" numeric(14,2) DEFAULT 0 NOT NULL,
    "stock_disponible" numeric(14,2) DEFAULT 0,
    "valeur_estimee_stock" numeric(18,2) DEFAULT 0,
    "notes" "text"
);


ALTER TABLE public.lots OWNER TO nbfodb_user;

--
-- Name: lots_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."lots_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lots_id_seq OWNER TO nbfodb_user;

--
-- Name: lots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."lots_id_seq" OWNED BY "public"."lots"."id";


--
-- Name: lots_traces; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."lots_traces" (
    "id" integer NOT NULL,
    "admission_id" integer,
    "lot_id" integer,
    "magasin_id" integer,
    "quantite_initiale" numeric(14,2),
    "quantite_restante" numeric(14,2),
    "date_reception" "date",
    "date_expiration" "date",
    "numero_lot" character varying(50),
    "statut" character varying(20) DEFAULT 'actif'::character varying
);


ALTER TABLE public.lots_traces OWNER TO nbfodb_user;

--
-- Name: lots_traces_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."lots_traces_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lots_traces_id_seq OWNER TO nbfodb_user;

--
-- Name: lots_traces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."lots_traces_id_seq" OWNED BY "public"."lots_traces"."id";


--
-- Name: magasins; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."magasins" (
    "id" integer NOT NULL,
    "nom" character varying(100) NOT NULL,
    "region_id" integer,
    "code" character varying(10) NOT NULL
);


ALTER TABLE public.magasins OWNER TO nbfodb_user;

--
-- Name: magasins_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."magasins_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.magasins_id_seq OWNER TO nbfodb_user;

--
-- Name: magasins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."magasins_id_seq" OWNED BY "public"."magasins"."id";


--
-- Name: messages; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."messages" (
    "id" integer NOT NULL,
    "expediteur_id" integer NOT NULL,
    "destinataire_id" integer NOT NULL,
    "expediteur" character varying(100),
    "objet" character varying(255) NOT NULL,
    "contenu" "text" NOT NULL,
    "date" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "lu" boolean DEFAULT false,
    "type_notification" character varying(50) DEFAULT 'interne'::character varying
);


ALTER TABLE public.messages OWNER TO nbfodb_user;

--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."messages_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.messages_id_seq OWNER TO nbfodb_user;

--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."messages_id_seq" OWNED BY "public"."messages"."id";


--
-- Name: operations; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."operations" (
    "id" integer NOT NULL,
    "utilisateur" character varying(50) NOT NULL,
    "type_operation" character varying(10) NOT NULL,
    "montant" numeric(12,2) NOT NULL,
    "solde_apres" numeric(12,2),
    "date_operation" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "operations_type_operation_check" CHECK ((("type_operation")::"text" = ANY ((ARRAY['credit'::character varying, 'debit'::character varying])::"text"[])))
);


ALTER TABLE public.operations OWNER TO nbfodb_user;

--
-- Name: operations_caisse; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."operations_caisse" (
    "id" integer NOT NULL,
    "utilisateur" character varying(50) NOT NULL,
    "type_operation" character varying(20) NOT NULL,
    "montant" numeric(12,2) NOT NULL,
    "solde_apres" numeric(12,2),
    "producteur" character varying(100),
    "description" "text",
    "date_operation" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "caisse_id" integer,
    "lot_id" integer,
    "producteur_id" integer
);


ALTER TABLE public.operations_caisse OWNER TO nbfodb_user;

--
-- Name: operations_caisse_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."operations_caisse_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operations_caisse_id_seq OWNER TO nbfodb_user;

--
-- Name: operations_caisse_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."operations_caisse_id_seq" OWNED BY "public"."operations_caisse"."id";


--
-- Name: operations_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."operations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operations_id_seq OWNER TO nbfodb_user;

--
-- Name: operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."operations_id_seq" OWNED BY "public"."operations"."id";


--
-- Name: producteurs; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."producteurs" (
    "id" integer NOT NULL,
    "nom_producteur" character varying(100) NOT NULL,
    "tel_producteur" character varying(20) NOT NULL,
    "type_producteur" character varying(50),
    "carte_membre" boolean DEFAULT false,
    "points_fidelite" integer DEFAULT 0,
    "solde" numeric(12,2) DEFAULT 0,
    "statut" character varying(20) DEFAULT 'en_attente'::character varying,
    "region_id" integer,
    "departement_id" integer,
    "arrondissement_id" integer,
    "localite" character varying(100),
    "matricule" character varying(50),
    "date_integration" "date" DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT "producteurs_points_fidelite_check" CHECK (("points_fidelite" >= 0)),
    CONSTRAINT "producteurs_solde_check" CHECK (("solde" >= (0)::numeric)),
    CONSTRAINT "producteurs_type_producteur_check" CHECK ((("type_producteur")::"text" = ANY ((ARRAY['agriculteur'::character varying, 'Ã©leveur'::character varying, 'pÃªcheur'::character varying, 'artisan'::character varying, 'alimentaire manufacture'::character varying, 'coopÃ©rative'::character varying, 'individuel'::character varying, 'autre'::character varying])::"text"[])))
);


ALTER TABLE public.producteurs OWNER TO nbfodb_user;

--
-- Name: producteurs_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."producteurs_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.producteurs_id_seq OWNER TO nbfodb_user;

--
-- Name: producteurs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."producteurs_id_seq" OWNED BY "public"."producteurs"."id";


--
-- Name: quality_coeff; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."quality_coeff" (
    "qual" character(1) NOT NULL,
    "coef" numeric(6,4) NOT NULL,
    CONSTRAINT "quality_coeff_coef_check" CHECK (("coef" > (0)::numeric))
);


ALTER TABLE public.quality_coeff OWNER TO nbfodb_user;

--
-- Name: realized_gains; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."realized_gains" (
    "id" integer NOT NULL,
    "lot_id" integer,
    "virtual_revenue_id" integer,
    "amount" numeric(18,2) NOT NULL,
    "details" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "gross_amount" numeric(18,2),
    "tax_amount" numeric(18,2),
    "net_amount" numeric(18,2)
);


ALTER TABLE public.realized_gains OWNER TO nbfodb_user;

--
-- Name: realized_gains_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

ALTER TABLE "public"."realized_gains" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."realized_gains_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: regions; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."regions" (
    "id" integer NOT NULL,
    "nom" character varying(100) NOT NULL
);


ALTER TABLE public.regions OWNER TO nbfodb_user;

--
-- Name: regions_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."regions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.regions_id_seq OWNER TO nbfodb_user;

--
-- Name: regions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."regions_id_seq" OWNED BY "public"."regions"."id";


--
-- Name: retraits; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."retraits" (
    "id" integer NOT NULL,
    "lot_id" integer NOT NULL,
    "utilisateur" character varying(50) NOT NULL,
    "type_retrait" character varying(20) NOT NULL,
    "quantite" numeric(14,2) NOT NULL,
    "unite" character varying(20) NOT NULL,
    "prix_ref" numeric(14,2) NOT NULL,
    "valeur_totale" numeric(14,2),
    "date_sortie" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "destination_producteur_id" integer,
    "montant_du" numeric(14,2),
    "mode_paiement" character varying(20),
    "points_utilises" numeric(6,2),
    "statut_paiement" character varying(20),
    "destination_client" "text",
    "destination_magasin_id" integer,
    "motif" "text",
    "magasin_id" integer NOT NULL,
    "coef_qualite" numeric(6,2),
    "taux_tax" numeric(6,2),
    "region_id" integer,
    "departement_id" integer,
    "arrondissement_id" integer,
    "localite" character varying(255),
    "admission_id" integer,
    CONSTRAINT "retraits_mode_paiement_check" CHECK ((("mode_paiement")::"text" = ANY ((ARRAY['liquide'::character varying, 'mobile'::character varying, 'dette'::character varying])::"text"[]))),
    CONSTRAINT "retraits_statut_paiement_check" CHECK ((("statut_paiement")::"text" = ANY ((ARRAY['comptant'::character varying, 'differe'::character varying])::"text"[]))),
    CONSTRAINT "retraits_type_retrait_check" CHECK ((("type_retrait")::"text" = ANY ((ARRAY['producteur'::character varying, 'client'::character varying, 'magasin'::character varying, 'destruction'::character varying])::"text"[])))
);


ALTER TABLE public.retraits OWNER TO nbfodb_user;

--
-- Name: retraits_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."retraits_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.retraits_id_seq OWNER TO nbfodb_user;

--
-- Name: retraits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."retraits_id_seq" OWNED BY "public"."retraits"."id";


--
-- Name: stocks; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."stocks" AS
 SELECT "a"."lot_id",
    "a"."magasin_id",
    "l"."description",
    "l"."prix_ref",
    "l"."unites_admises",
    "l"."categorie",
    "a"."unite",
    (COALESCE("sum"("a"."quantite"), (0)::numeric) - COALESCE(( SELECT "sum"("r"."quantite") AS "sum"
           FROM "public"."retraits" "r"
          WHERE (("r"."lot_id" = "a"."lot_id") AND ("r"."magasin_id" = "a"."magasin_id"))), (0)::numeric)) AS "stock_actuel",
    "max"("a"."date_reception") AS "derniere_reception"
   FROM ("public"."admissions" "a"
     LEFT JOIN "public"."lots" "l" ON (("a"."lot_id" = "l"."id")))
  GROUP BY "a"."lot_id", "a"."magasin_id", "l"."description", "l"."prix_ref", "l"."unites_admises", "l"."categorie", "a"."unite"
 HAVING ((COALESCE("sum"("a"."quantite"), (0)::numeric) - COALESCE(( SELECT "sum"("r"."quantite") AS "sum"
           FROM "public"."retraits" "r"
          WHERE (("r"."lot_id" = "a"."lot_id") AND ("r"."magasin_id" = "a"."magasin_id"))), (0)::numeric)) > (0)::numeric);


ALTER VIEW public.stocks OWNER TO nbfodb_user;

--
-- Name: tax_rates; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."tax_rates" (
    "category" character varying(100) NOT NULL,
    "tax_rate" numeric(5,4) NOT NULL,
    CONSTRAINT "tax_rates_tax_rate_check" CHECK ((("tax_rate" >= (0)::numeric) AND ("tax_rate" <= (1)::numeric)))
);


ALTER TABLE public.tax_rates OWNER TO nbfodb_user;

--
-- Name: transferts; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."transferts" (
    "id" integer NOT NULL,
    "lot_id" integer,
    "magasin_depart" integer,
    "magasin_destination" integer,
    "chauffeur_id" character varying(50),
    "quantite" numeric(10,2) NOT NULL,
    "unite" character varying(20),
    "prix_ref" numeric(10,2),
    "statut" character varying(20) DEFAULT 'en_transit'::character varying,
    "motif" "text",
    "utilisateur" character varying(100),
    "date_creation" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "date_reception" timestamp without time zone,
    "validation_auditeur" boolean DEFAULT false
);


ALTER TABLE public.transferts OWNER TO nbfodb_user;

--
-- Name: transferts_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."transferts_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transferts_id_seq OWNER TO nbfodb_user;

--
-- Name: transferts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."transferts_id_seq" OWNED BY "public"."transferts"."id";


--
-- Name: transferts_urgence; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."transferts_urgence" (
    "id" integer NOT NULL,
    "lot_id" integer,
    "magasin_id_depart" integer,
    "magasin_id_dest" integer,
    "quantite" numeric(10,2) NOT NULL,
    "chauffeur" character varying(255),
    "motif_urgence" "text",
    "admin_local_depart_ok" boolean DEFAULT false,
    "admin_local_dest_ok" boolean DEFAULT false,
    "audit_final_ok" boolean DEFAULT false,
    "statut" character varying(50) DEFAULT 'WAITING_LOCAL_VAL'::character varying,
    "date_creation" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "auditeur_id" integer
);


ALTER TABLE public.transferts_urgence OWNER TO nbfodb_user;

--
-- Name: transferts_urgence_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."transferts_urgence_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transferts_urgence_id_seq OWNER TO nbfodb_user;

--
-- Name: transferts_urgence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."transferts_urgence_id_seq" OWNED BY "public"."transferts_urgence"."id";


--
-- Name: users; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."users" (
    "id" character varying(50) NOT NULL,
    "username" character varying(50) NOT NULL,
    "password_hash" character varying(255) NOT NULL,
    "role" character varying(20) NOT NULL,
    "magasin_id" integer,
    "prenom" character varying(50),
    "nom" character varying(100),
    "email" character varying(100),
    "telephone" character varying(20),
    "created_at" timestamp without time zone DEFAULT "now"(),
    "last_login" timestamp without time zone,
    "statut" character varying(20) DEFAULT 'actif'::character varying,
    "avatar_url" "text",
    "matricule" character varying(50),
    CONSTRAINT "users_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['superadmin'::character varying, 'auditeur'::character varying, 'admin'::character varying, 'caisse'::character varying, 'stock'::character varying])::"text"[])))
);


ALTER TABLE public.users OWNER TO nbfodb_user;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

CREATE SEQUENCE "public"."users_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO nbfodb_user;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nbfodb_user
--

ALTER SEQUENCE "public"."users_id_seq" OWNED BY "public"."users"."id";


--
-- Name: virtual_revenues; Type: TABLE; Schema: public; Owner: nbfodb_user
--

CREATE TABLE "public"."virtual_revenues" (
    "id" integer NOT NULL,
    "lot_id" integer NOT NULL,
    "quantite" numeric(14,2) NOT NULL,
    "prix_ref" numeric(14,2) NOT NULL,
    "qual" character varying(10),
    "coef_qualite" numeric(6,4),
    "estimee" numeric(18,2) NOT NULL,
    "tax_rate" numeric(5,4) NOT NULL,
    "tax_amount" numeric(18,2) NOT NULL,
    "status" character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "realized_at" timestamp with time zone,
    "net_amount" numeric(18,2),
    "quantite_restante" numeric,
    "profit_unitaire_virtuel" numeric,
    "benefice_espere" numeric(15,2) DEFAULT 0,
    "admission_id" integer,
    CONSTRAINT "virtual_revenues_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending'::character varying, 'realized'::character varying, 'cancelled'::character varying])::"text"[])))
);


ALTER TABLE public.virtual_revenues OWNER TO nbfodb_user;

--
-- Name: view_alertes_expiration; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."view_alertes_expiration" AS
 SELECT "m"."nom" AS "magasin",
    "l"."description" AS "produit",
    "a"."quantite" AS "quantite_initiale",
    "a"."date_expiration",
    EXTRACT(day FROM ((("a"."date_expiration")::timestamp without time zone)::timestamp with time zone - "now"())) AS "jours_restants",
    "vr"."profit_unitaire_virtuel" AS "profit_en_danger"
   FROM ((("public"."admissions" "a"
     JOIN "public"."lots" "l" ON (("a"."lot_id" = "l"."id")))
     JOIN "public"."magasins" "m" ON (("a"."magasin_id" = "m"."id")))
     JOIN "public"."virtual_revenues" "vr" ON (("a"."id" = "vr"."lot_id")))
  WHERE (("a"."date_expiration" <= ("now"() + '48:00:00'::interval)) AND (("vr"."status")::"text" = 'pending'::"text"))
  ORDER BY "a"."date_expiration";


ALTER VIEW public.view_alertes_expiration OWNER TO nbfodb_user;

--
-- Name: view_audit_banque_interne; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."view_audit_banque_interne" AS
 SELECT "vr"."admission_id",
    "m"."nom" AS "magasin",
    "l"."description" AS "produit",
    "vr"."tax_amount" AS "profit_attendu_initial",
    COALESCE("sum"("bl"."montant_realise"), (0)::numeric) AS "profit_reel_encaisse",
    "vr"."quantite_restante",
    "vr"."status" AS "statut_lot",
    ("vr"."tax_amount" - COALESCE("sum"("bl"."montant_realise"), (0)::numeric)) AS "reste_a_percevoir"
   FROM (((("public"."virtual_revenues" "vr"
     JOIN "public"."lots" "l" ON (("vr"."lot_id" = "l"."id")))
     JOIN "public"."admissions" "a" ON (("vr"."admission_id" = "a"."id")))
     JOIN "public"."magasins" "m" ON (("a"."magasin_id" = "m"."id")))
     LEFT JOIN "public"."internal_bank_logs" "bl" ON (("vr"."admission_id" = "bl"."admission_id")))
  GROUP BY "vr"."admission_id", "m"."nom", "l"."description", "vr"."tax_amount", "vr"."quantite_restante", "vr"."status"
  ORDER BY "vr"."status" DESC, "m"."nom";


ALTER VIEW public.view_audit_banque_interne OWNER TO nbfodb_user;

--
-- Name: view_performance_financiere; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."view_performance_financiere" AS
 SELECT "m"."nom" AS "magasin",
    "l"."description" AS "produit",
    "sum"("b"."montant_realise") AS "profit_taxe_realise",
    "sum"("b"."difference_valeur") AS "gain_fraicheur_total",
    "sum"(("b"."montant_realise" + "b"."difference_valeur")) AS "performance_totale",
    "count"("b"."id") AS "nombre_operations"
   FROM ((("public"."internal_bank_logs" "b"
     JOIN "public"."lots" "l" ON (("b"."lot_id" = "l"."id")))
     JOIN "public"."admissions" "a" ON (("b"."admission_id" = "a"."id")))
     JOIN "public"."magasins" "m" ON (("a"."magasin_id" = "m"."id")))
  GROUP BY "m"."nom", "l"."description";


ALTER VIEW public.view_performance_financiere OWNER TO nbfodb_user;

--
-- Name: view_rapport_pertes; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."view_rapport_pertes" AS
 SELECT "r"."date_sortie",
    "r"."utilisateur" AS "responsable",
    "m"."nom" AS "magasin",
    "l"."description" AS "produit",
    (("r"."quantite" || ' '::"text") || ("r"."unite")::"text") AS "quantite_perdue",
    "r"."motif"
   FROM (("public"."retraits" "r"
     JOIN "public"."lots" "l" ON (("r"."lot_id" = "l"."id")))
     JOIN "public"."magasins" "m" ON (("r"."magasin_id" = "m"."id")))
  WHERE (("r"."type_retrait")::"text" = 'destruction'::"text")
  ORDER BY "r"."date_sortie" DESC;


ALTER VIEW public.view_rapport_pertes OWNER TO nbfodb_user;

--
-- Name: virtual_revenues_id_seq; Type: SEQUENCE; Schema: public; Owner: nbfodb_user
--

ALTER TABLE "public"."virtual_revenues" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."virtual_revenues_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vue_audit_recent; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."vue_audit_recent" AS
 SELECT "a"."id",
    "a"."date",
    "a"."utilisateur",
    "a"."action",
    'Admission'::"text" AS "type",
    "ad"."benefice_estime" AS "montant",
    "m"."nom" AS "magasin"
   FROM (("public"."audit" "a"
     LEFT JOIN "public"."admissions" "ad" ON (("a"."action" ~~ (('%admission%'::"text" || "ad"."id") || '%'::"text"))))
     LEFT JOIN "public"."magasins" "m" ON (("ad"."magasin_id" = "m"."id")))
  WHERE ("a"."date" >= (CURRENT_DATE - '7 days'::interval))
  ORDER BY "a"."date" DESC
 LIMIT 20;


ALTER VIEW public.vue_audit_recent OWNER TO nbfodb_user;

--
-- Name: vue_performance_magasins; Type: VIEW; Schema: public; Owner: nbfodb_user
--

CREATE VIEW "public"."vue_performance_magasins" AS
 SELECT "m"."id" AS "magasin_id",
    "m"."nom" AS "nom_magasin",
    "count"("a"."id") AS "nombre_admissions",
    COALESCE("sum"("a"."quantite"), (0)::numeric) AS "quantite_totale",
    COALESCE("sum"("a"."benefice_estime"), (0)::numeric) AS "profit_virtuel_genere",
    COALESCE("sum"("a"."valeur_totale"), (0)::numeric) AS "valeur_totale_admise",
    "count"(
        CASE
            WHEN ("a"."coef_qualite" < 0.8) THEN 1
            ELSE NULL::integer
        END) AS "alertes_qualite"
   FROM ("public"."magasins" "m"
     LEFT JOIN "public"."admissions" "a" ON ((("a"."magasin_id" = "m"."id") AND ("a"."date_reception" >= (CURRENT_DATE - '30 days'::interval)))))
  GROUP BY "m"."id", "m"."nom"
  ORDER BY COALESCE("sum"("a"."benefice_estime"), (0)::numeric) DESC;


ALTER VIEW public.vue_performance_magasins OWNER TO nbfodb_user;

--
-- Name: admissions id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."admissions_id_seq"'::"regclass");


--
-- Name: arrondissements id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."arrondissements" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."arrondissements_id_seq"'::"regclass");


--
-- Name: audit id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."audit" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."audit_id_seq"'::"regclass");


--
-- Name: caisse id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."caisse_id_seq"'::"regclass");


--
-- Name: caisse_lignes id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse_lignes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."caisse_lignes_id_seq"'::"regclass");


--
-- Name: cheques id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."cheques" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cheques_id_seq"'::"regclass");


--
-- Name: departements id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departements" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."departements_id_seq"'::"regclass");


--
-- Name: employers id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."employers" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."employers_id_seq"'::"regclass");


--
-- Name: internal_bank_logs id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."internal_bank_logs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."internal_bank_logs_id_seq"'::"regclass");


--
-- Name: logs_deploiement id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."logs_deploiement" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."logs_deploiement_id_seq"'::"regclass");


--
-- Name: lots id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."lots_id_seq"'::"regclass");


--
-- Name: lots_traces id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots_traces" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."lots_traces_id_seq"'::"regclass");


--
-- Name: magasins id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."magasins" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."magasins_id_seq"'::"regclass");


--
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."messages" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."messages_id_seq"'::"regclass");


--
-- Name: operations id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."operations_id_seq"'::"regclass");


--
-- Name: operations_caisse id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations_caisse" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."operations_caisse_id_seq"'::"regclass");


--
-- Name: producteurs id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."producteurs_id_seq"'::"regclass");


--
-- Name: regions id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."regions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."regions_id_seq"'::"regclass");


--
-- Name: retraits id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."retraits_id_seq"'::"regclass");


--
-- Name: transferts id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."transferts_id_seq"'::"regclass");


--
-- Name: transferts_urgence id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts_urgence" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."transferts_urgence_id_seq"'::"regclass");


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."users" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."users_id_seq"'::"regclass");


--
-- Data for Name: admissions; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."admissions" ("id", "lot_id", "producteur_id", "quantite", "unite", "prix_ref", "date_reception", "date_expiration", "magasin_id", "utilisateur", "valeur_totale", "benefice_estime", "coef_qualite", "taux_tax", "region_id", "departement_id", "arrondissement_id", "localite", "mode_paiement", "montant_verse", "grade_qualite", "user_id") FROM stdin;
10	5	12	100.00	g	500.00	2026-01-31	\N	1	superadmin	\N	\N	1.00	\N	\N	\N	\N	\N	mobile_money	\N	\N	\N
11	5	12	100.00	g	500.00	2025-12-22	2026-01-31	1	superadmin	\N	\N	1.00	\N	\N	\N	\N	\N	mobile_money	\N	\N	\N
12	9	350	5.00	kg	1200.00	2025-12-22	2026-01-03	12	admin	\N	\N	0.90	\N	\N	\N	\N	\N	solde	\N	\N	\N
27	13	362	1000.00	kg	650.00	2025-12-26	2026-01-10	2	agent_system	650000.00	81250.00	1.00	0.13	\N	\N	\N	\N	solde	568750.00	A	\N
28	12	362	1000.00	kg	650.00	2025-12-27	2026-01-10	2	agent_system	650000.00	84500.00	1.00	0.13	\N	\N	\N	\N	solde	565500.00	A	\N
29	10	359	500.00	kg	2500.00	2025-12-27	2026-01-09	2	agent_system	1250000.00	168750.00	1.00	0.14	\N	\N	\N	\N	solde	1081250.00	A	\N
30	8	350	345.00	kg	2500.00	2025-12-27	2026-01-11	8	ndjomfils	862500.00	107812.50	1.00	0.13	\N	\N	\N	\N	solde	754687.50	A	\N
31	14	352	6000.00	kg	500.00	2025-12-27	2026-01-31	21	ndjomfils	3000000.00	210000.00	1.00	0.07	\N	\N	\N	\N	mobile_money	2790000.00	A	\N
32	6	343	5000.00	kg	5000.00	2025-12-27	\N	19	ndjomfils	25000000.00	1250000.00	1.00	0.05	\N	\N	\N	\N	solde	23750000.00	A	\N
33	17	327	180.00	sacs	17850.00	2025-12-27	2026-01-10	4	ndjomfils	3213000.00	417690.00	1.00	0.13	\N	\N	\N	\N	solde	2795310.00	A	\N
34	15	362	500.00	litres	1400.00	2025-12-27	\N	2	ndjomfils	700000.00	35000.00	1.00	0.05	\N	\N	\N	\N	solde	665000.00	A	\N
35	16	311	500.00	litres	5000.00	2025-12-27	\N	3	ndjomfils	2500000.00	125000.00	1.00	0.05	\N	\N	\N	\N	solde	2375000.00	A	\N
36	9	349	500.00	kg	2500.00	2025-12-27	2026-01-03	13	ndjomfils	1250000.00	206250.00	1.00	0.17	\N	\N	\N	\N	solde	1043750.00	A	\N
37	15	362	800.00	litres	1400.00	2025-12-27	\N	1	ndjomfils	1120000.00	56000.00	1.00	0.05	\N	\N	\N	\N	solde	1064000.00	A	\N
38	13	351	1000.00	kg	650.00	2025-12-27	2026-01-03	8	ndjomfils	650000.00	120250.00	1.00	0.19	\N	\N	\N	\N	mobile_money	529750.00	A	\N
39	8	350	500.00	kg	2500.00	2025-12-28	2026-01-17	9	superadmin	1000000.00	120000.00	0.80	0.12	\N	\N	\N	\N	mobile_money	880000.00	C	\N
40	18	348	5000.00	unites	4500.00	2026-01-14	\N	19	superadmin	22500000.00	1125000.00	1.00	0.05	\N	\N	\N	\N	solde	21375000.00	A	\N
41	17	354	30.00	sacs	17850.00	2026-01-16	2026-01-25	2	ndjomfils	428400.00	66402.00	0.80	0.16	\N	\N	\N	\N	solde	361998.00	C	\N
44	5	363	47.00	g	5000.00	2026-01-18	\N	16	superadmin	235000.00	11750.00	\N	0.05	\N	\N	\N	\N	solde	223250.00	A	\N
45	17	362	500.00	sacs	17850.00	2026-01-21	2026-01-30	19	superadmin	8925000.00	1383375.00	1.00	0.16	\N	\N	\N	\N	solde	7541625.00	A	\N
46	15	363	75.00	litres	1400.00	2026-01-23	\N	17	superadmin	105000.00	5250.00	\N	0.05	\N	\N	\N	\N	solde	99750.00	A	\N
47	16	315	1200.00	litres	5000.00	2026-01-24	2026-07-24	4	superadmin	6000000.00	420000.00	1.00	0.07	\N	\N	\N	\N	mobile_money	5580000.00	A	\N
48	10	345	2500.00	kg	2500.00	2026-01-24	2026-02-07	6	superadmin	6250000.00	812500.00	1.00	0.13	\N	\N	\N	\N	solde	5437500.00	A	\N
49	14	362	1000.00	kg	500.00	2026-01-24	2026-07-25	2	superadmin	500000.00	25000.00	1.00	0.05	\N	\N	\N	\N	solde	475000.00	A	\N
\.


--
-- Data for Name: arrondissements; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."arrondissements" ("id", "nom", "departement_id", "code") FROM stdin;
1	Ngaoundal	1	DJE_001
2	Tibati	1	DJE_002
3	Galim-TignÃ¨re	2	FDE_001
4	Kontcha	2	FDE_002
5	Mayo-BalÃ©o	2	FDE_003
6	TignÃ¨re	2	FDE_004
7	Bankim	3	MBY_001
8	Banyo	3	MBY_002
9	Mayo-DarlÃ©	3	MBY_003
10	Dir	4	MBE_001
11	Djohong	4	MBE_002
12	Meiganga	4	MBE_003
13	Ngaoui	4	MBE_004
14	Belel	5	VIN_001
15	Martap	5	VIN_002
16	Mbe	5	VIN_003
17	Nganha	5	VIN_004
18	NgaoundÃ©rÃ© I	5	VIN_005
19	NgaoundÃ©rÃ© II	5	VIN_006
20	NgaoundÃ©rÃ© III	5	VIN_007
21	Nyambaka	5	VIN_008
22	Bibey	6	HSA_001
23	Lembe-Yezoum	6	HSA_002
24	Mbandjock	6	HSA_003
25	Minta	6	HSA_004
26	Nanga-Eboko	6	HSA_005
27	Nkoteng	6	HSA_006
28	Nsem	6	HSA_007
29	Batchenga	7	LEK_001
30	Ebebda	7	LEK_002
31	Elig-Mfomo	7	LEK_003
32	Evodoula	7	LEK_004
33	Lobo	7	LEK_005
34	MonatÃ©lÃ©	7	LEK_006
35	Obala	7	LEK_007
36	Okola	7	LEK_008
37	Sa'a	7	LEK_009
38	Bafia	8	MBI_001
39	Bokito	8	MBI_002
40	Deuk	8	MBI_003
41	Kiiki	8	MBI_004
42	Kon-Yambetta	8	MBI_005
43	MakÃ©nÃ©nÃ©	8	MBI_006
44	NdikinimÃ©ki	8	MBI_007
45	Nitoukou	8	MBI_008
46	Ombessa	8	MBI_009
47	Mbangassina	9	MBK_001
48	NgambÃ¨-Tikar	9	MBK_002
49	Ngoro	9	MBK_003
50	Ntui	9	MBK_004
51	Yoko	9	MBK_005
52	Afanloum	10	MFA_001
53	Assamba	10	MFA_002
54	AwaÃ©	10	MFA_003
55	Edzendouan	10	MFA_004
56	Esse	10	MFA_005
57	Mfou	10	MFA_006
58	Nkolafamba	10	MFA_007
59	Soa	10	MFA_008
60	Akono	11	MAK_001
61	Bikok	11	MAK_002
62	Mbankomo	11	MAK_003
63	Ngoumou	11	MAK_004
64	YaoundÃ© I	12	MFO_001
65	YaoundÃ© II	12	MFO_002
66	YaoundÃ© III	12	MFO_003
67	YaoundÃ© IV	12	MFO_004
68	YaoundÃ© V	12	MFO_005
69	YaoundÃ© VI	12	MFO_006
70	YaoundÃ© VII	12	MFO_007
75	Ã‰sÃ©ka	13	NYK_001
71	Biyouha	13	NYK_002
72	Bondjock	13	NYK_003
73	Bot-Makak	13	NYK_004
74	Dibang	13	NYK_005
76	Makak	13	NYK_006
77	Matomb	13	NYK_007
78	Messondo	13	NYK_008
79	Ngog-Mapubi	13	NYK_009
80	Nguibassal	13	NYK_010
81	Akonolinga	14	NYM_001
82	Ayos	14	NYM_002
83	Endom	14	NYM_003
84	Mengang	14	NYM_004
85	Nyakokombo	14	NYM_005
355	Mbalmayo	15	NYS_001
356	Mengueme	15	NYS_002
357	Ngomedzap	15	NYS_003
358	Nkolmetet	15	NYS_004
86	Gari-Gombo	16	BNG_001
87	Moloundou	16	BNG_002
88	SalapoumbÃ©	16	BNG_003
89	Yokadouma	16	BNG_004
90	Abong-Mbang	17	HNY_001
91	Bebend	17	HNY_002
92	Dimako	17	HNY_003
93	Dja	17	HNY_004
95	DoumÃ©	17	HNY_005
94	Doumaintang	17	HNY_006
96	LomiÃ©	17	HNY_007
97	Mboanz	17	HNY_008
98	Mboma	17	HNY_009
99	Messamena	17	HNY_010
100	Messok	17	HNY_011
101	Ngoyla	17	HNY_012
102	Nguelemendouka	17	HNY_013
103	Somalomo	17	HNY_014
104	Batouri	18	KAD_001
105	BombÃ©	18	KAD_002
106	Kette	18	KAD_003
107	Mbang	18	KAD_004
108	Mbotoro	18	KAD_005
109	Ndelele	18	KAD_006
110	Ndem-Nam	18	KAD_007
111	BÃ©labo	19	LOM_001
114	BÃ©tarÃ©-Oya	19	LOM_002
112	Bertoua I	19	LOM_003
113	Bertoua II	19	LOM_004
115	Diang	19	LOM_005
116	Garoua-BoulaÃ¯	19	LOM_006
117	Mandjou	19	LOM_007
118	Ngoura	19	LOM_008
119	Bogo	20	DIA_001
120	Dargala	20	DIA_002
121	Gazawa	20	DIA_003
122	Maroua I	20	DIA_004
123	Maroua II	20	DIA_005
124	Maroua III	20	DIA_006
125	Meri	20	DIA_007
126	Ndoukoula	20	DIA_008
127	PettÃ©	20	DIA_009
128	Blangoua	21	LCH_001
129	Darak	21	LCH_002
130	Fotokol	21	LCH_003
131	Goulfey	21	LCH_004
132	Hile-Alifa	21	LCH_005
133	KoussÃ©ri	21	LCH_006
134	Logone-Birni	21	LCH_007
135	Makary	21	LCH_008
136	Waza	21	LCH_009
137	Zina	21	LCH_010
138	Datcheka	22	MDN_001
139	Gobo	22	MDN_002
140	GuÃ©rÃ©	22	MDN_003
141	KaÃ¯-KaÃ¯	22	MDN_004
142	Kalfou	22	MDN_005
143	Kar-Hay	22	MDN_006
144	Maga	22	MDN_007
145	Tchati-Bali	22	MDN_008
146	Vele	22	MDN_009
147	Wina	22	MDN_010
148	Yagoua	22	MDN_011
149	Guidiguis	23	MKN_001
150	KaÃ©lÃ©	23	MKN_002
151	Mindif	23	MKN_003
152	Moulvoudaye	23	MKN_004
153	Moutourwa	23	MKN_005
154	Porhi	23	MKN_006
155	Taibong	23	MKN_007
156	Kolofata	24	MSA_001
157	Mora	24	MSA_002
158	TokombÃ©rÃ©	24	MSA_003
159	Bourrha	25	MTS_001
160	Hina	25	MTS_002
161	Koza	25	MTS_003
162	Mayo-Moskota	25	MTS_004
163	Mogode	25	MTS_005
164	Mokolo	25	MTS_006
165	SoulÃ©dÃ©-Roua	25	MTS_007
187	Abo Fiko (BonalÃ©a)	26	MOU_001
188	BarÃ©-Bakem	26	MOU_002
189	Dibombari	26	MOU_003
190	Loum	26	MOU_004
191	Manjo	26	MOU_005
192	Mbanga	26	MOU_006
193	Melong	26	MOU_007
194	Mombo	26	MOU_008
195	Njombe-Penja	26	MOU_009
196	Nkongsamba I	26	MOU_010
197	Nkongsamba II	26	MOU_011
198	Nkongsamba III	26	MOU_012
199	Nlonako	26	MOU_013
183	Nkondjock	27	NKA_001
184	Nord-MakombÃ©	27	NKA_002
185	Yabassi	27	NKA_003
186	Yingui	27	NKA_004
174	Ã‰dÃ©a I	28	SMA_001
175	Ã‰dÃ©a II	28	SMA_002
172	Dibamba	28	SMA_003
173	DizanguÃ©	28	SMA_004
176	Massock-Songloulou	28	SMA_005
177	Mouanko	28	SMA_006
178	Ndom	28	SMA_007
179	Ngambe	28	SMA_008
180	Ngwei	28	SMA_009
181	Nyanon	28	SMA_010
182	Pouma	28	SMA_011
166	Douala I	29	WOU_001
167	Douala II	29	WOU_002
168	Douala III	29	WOU_003
169	Douala IV	29	WOU_004
170	Douala V	29	WOU_005
171	Douala VI	29	WOU_006
200	BaschÃ©o	30	BEN_001
201	Bibemi	30	BEN_002
202	Dembo	30	BEN_003
203	Demsa	30	BEN_004
204	Garoua I	30	BEN_005
205	Garoua II	30	BEN_006
206	Garoua III	30	BEN_007
207	Lagdo	30	BEN_008
208	Mayo-Hourna	30	BEN_009
209	Pitoa	30	BEN_010
210	Tcheboa	30	BEN_011
211	Touroua	30	BEN_012
212	Beka	31	FAR_001
213	Poli	31	FAR_002
214	Figuil	32	MLO_001
215	Guider	32	MLO_002
216	Mayo-Oulo	32	MLO_003
217	Madingring	33	MRE_001
218	Rey-Bouba	33	MRE_002
219	TchollirÃ©	33	MRE_003
220	Touboro	33	MRE_004
221	Belo	34	BOY_001
222	Bum	34	BOY_002
223	Fundong	34	BOY_003
224	Njinikom	34	BOY_004
225	Jakiri	35	BUI_001
226	Kumbo	35	BUI_002
227	Mbven	35	BUI_003
228	Nkum	35	BUI_004
229	Noni	35	BUI_005
230	Oku	35	BUI_006
231	Ako	36	DMA_001
232	Misaje	36	DMA_002
233	Ndu	36	DMA_003
234	NkambÃ©	36	DMA_004
235	Nwa	36	DMA_005
236	Fungom	37	MEN_001
237	Furu-Awa	37	MEN_002
238	Menchum Valley	37	MEN_003
239	Wum	37	MEN_004
240	Bafut	38	MEZ_001
241	Bali	38	MEZ_002
242	Bamenda I	38	MEZ_003
243	Bamenda II	38	MEZ_004
244	Bamenda III	38	MEZ_005
245	Santa	38	MEZ_006
246	Tubah	38	MEZ_007
247	Batibo	39	MOM_001
248	Mbengwi	39	MOM_002
249	Ngie	39	MOM_003
250	Njikwa	39	MOM_004
251	Widikum-Menka	39	MOM_005
252	Babessi	40	NKE_001
253	Balikumbat	40	NKE_002
254	Ndop	40	NKE_003
255	Babadjou	41	BAM_001
256	Batcham	41	BAM_002
257	Galim	41	BAM_003
258	Mbouda	41	BAM_004
259	Bafang	42	HNK_001
260	Bakou	42	HNK_002
261	Bana	42	HNK_003
262	Bandja	42	HNK_004
263	Banka	42	HNK_005
264	Banwa	42	HNK_006
265	KÃ©kem	42	HNK_007
266	Baham	43	HPL_001
267	Bamendjou	43	HPL_002
268	Bangou	43	HPL_003
269	BatiÃ©	43	HPL_004
270	Bayangam	44	KKH_001
271	Djebem	44	KKH_002
272	Poumougne	44	KKH_003
273	Dschang	45	MNO_001
274	FokouÃ©	45	MNO_002
275	Fongo-Tongo	45	MNO_003
276	Nkong-Ni	45	MNO_004
277	Penka-Michel	45	MNO_005
278	Santchou	45	MNO_006
279	Bafoussam I	46	MIF_001
280	Bafoussam II	46	MIF_002
281	Bafoussam III	46	MIF_003
282	BangangtÃ©	47	NDE_001
283	Bassamba	47	NDE_002
284	Bazou	47	NDE_003
285	Tonga	47	NDE_004
286	Bangourain	48	NOU_001
287	Foumban	48	NOU_002
288	Foumbot	48	NOU_003
289	Kouoptamo	48	NOU_004
290	Koutaba	48	NOU_005
291	Magba	48	NOU_006
292	Malentouen	48	NOU_007
293	Massangam	48	NOU_008
294	Njimom	48	NOU_009
295	Bengbis	49	DJL_001
296	Djoum	49	DJL_002
297	Meyomessala	49	DJL_003
298	Meyomessi	49	DJL_004
299	Mintom	49	DJL_005
300	Oveng	49	DJL_006
301	SangmÃ©lima	49	DJL_007
302	ZoÃ©tÃ©lÃ©	49	DJL_008
303	Biwong-Bane	50	MVI_001
304	Biwong-Bulu	50	MVI_002
305	Ebolowa I	50	MVI_003
306	Ebolowa II	50	MVI_004
307	Efoulan	50	MVI_005
308	Mengong	50	MVI_006
309	Mvangan	50	MVI_007
310	Ngoulemakong	50	MVI_008
311	Akom II	51	OCE_001
312	Bipindi	51	OCE_002
313	Campo	51	OCE_003
314	Kribi I	51	OCE_004
315	Kribi II	51	OCE_005
316	Lokoundje	51	OCE_006
317	Lolodorf	51	OCE_007
318	Mvengue	51	OCE_008
319	Niete	51	OCE_009
320	Ambam	52	VNT_001
321	KyÃ©-Ossi	52	VNT_002
322	Ma'an	52	VNT_003
323	Olamze	52	VNT_004
324	Buea	53	FAK_001
325	LimbÃ© I	53	FAK_002
326	LimbÃ© II	53	FAK_003
327	LimbÃ© III	53	FAK_004
328	Muyuka	53	FAK_005
329	Tiko	53	FAK_006
330	West Coast	53	FAK_007
331	Bangem	54	KPM_001
332	Nguti	54	KPM_002
333	Tombel	54	KPM_003
334	Alou	55	LEB_001
335	Fontem	55	LEB_002
336	Wabane	55	LEB_003
337	Akwaya	56	MAN_001
338	Eyumodjock	56	MAN_002
339	MamfÃ© Central	56	MAN_003
340	Upper Banyang	56	MAN_004
341	Konye	57	MEM_001
342	Kumba I	57	MEM_002
343	Kumba II	57	MEM_003
344	Kumba III	57	MEM_004
345	Mbonge	57	MEM_005
346	Bamusso	58	NDI_001
347	Dikome-Balue	58	NDI_002
348	Ekondo-Titi	58	NDI_003
349	Idabato	58	NDI_004
350	Isanguele	58	NDI_005
351	Kombo-Abedimo	58	NDI_006
352	Kombo-Itindi	58	NDI_007
353	Mundemba	58	NDI_008
354	Toko	58	NDI_009
\.


--
-- Data for Name: audit; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."audit" ("id", "date", "utilisateur", "action") FROM stdin;
\.


--
-- Data for Name: caisse; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."caisse" ("id", "benefices_virtuels") FROM stdin;
\.


--
-- Data for Name: caisse_lignes; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."caisse_lignes" ("id", "caisse_id", "lot_id", "producteur_id", "type_operation", "montant", "statut", "reference") FROM stdin;
\.


--
-- Data for Name: cheques; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."cheques" ("id", "numero_cheque", "banque", "montant", "emetteur", "date_enregistrement") FROM stdin;
\.


--
-- Data for Name: departement_codes; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."departement_codes" ("departement_id", "code") FROM stdin;
1	DJE
2	FDE
3	MBY
4	MBE
5	VIN
6	HSA
7	LEK
8	MBI
9	MBK
10	MFA
11	MAK
12	MFO
13	NYK
14	NYM
15	NYS
16	BNG
17	HNY
18	KAD
19	LOM
20	DIA
21	LCH
22	MDN
23	MKN
24	MSA
25	MTS
26	MOU
27	NKA
28	SMA
29	WOU
30	BEN
31	FAR
32	MLO
33	MRE
34	BOY
35	BUI
36	DMA
37	MEN
38	MEZ
39	MOM
40	NKE
41	BAM
42	HNK
43	HPL
44	KKH
45	MNO
46	MIF
47	NDE
48	NOU
49	DJL
50	MVI
51	OCE
52	VNT
53	FAK
54	KPM
55	LEB
56	MAN
57	MEM
58	NDI
\.


--
-- Data for Name: departements; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."departements" ("id", "nom", "region_id") FROM stdin;
1	DjÃ©rem	5
2	Faro-et-DÃ©o	5
3	Mayo-Banyo	5
4	MbÃ©rÃ©	5
5	Vina	5
6	Haute-Sanaga	1
7	LekiÃ©	1
8	Mbam-et-Inoubou	1
9	Mbam-et-Kim	1
10	MÃ©fou-et-Afamba	1
11	MÃ©fou-et-Akono	1
12	Mfoundi	1
13	Nyong-et-KellÃ©	1
14	Nyong-et-Mfoumou	1
15	Nyong-et-So'o	1
16	Boumba-et-Ngoko	6
17	Haut-Nyong	6
18	Kadey	6
19	Lom-et-DjÃ©rem	6
20	DiamarÃ©	4
21	Logone-et-Chari	4
22	Mayo-Danay	4
23	Mayo-Kani	4
24	Mayo-Sava	4
25	Mayo-Tsanaga	4
26	Moungo	2
27	Nkam	2
28	Sanaga-Maritime	2
29	Wouri	2
30	BÃ©nouÃ©	3
31	Faro	3
32	Mayo-Louti	3
33	Mayo-Rey	3
34	Boyo	9
35	Bui	9
36	Donga-Mantung	9
37	Menchum	9
38	Mezam	9
39	Momo	9
40	Ngo-Ketunjia	9
41	Bamboutos	7
42	Haut-Nkam	7
43	Hauts-Plateaux	7
44	Koung-Khi	7
45	Menoua	7
46	Mifi	7
47	NdÃ©	7
48	Noun	7
49	Dja-et-Lobo	8
50	Mvila	8
51	OcÃ©an	8
52	VallÃ©e-du-Ntem	8
53	Fako	10
54	KoupÃ©-Manengouba	10
55	Lebialem	10
56	Manyu	10
57	Meme	10
58	Ndian	10
\.


--
-- Data for Name: employers; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."employers" ("id", "magasin_id", "nom", "role", "contact", "date_embauche", "statut", "matricule") FROM stdin;
CE01_manutentionnaire_001	1	manutentionnaire_Nom01_CE01	manutentionnaire	69901001	2025-12-17	actif	manutentionnaire_12-2025_001
CE01_manutentionnaire_002	1	manutentionnaire_Nom02_CE01	manutentionnaire	69901002	2025-12-16	actif	manutentionnaire_12-2025_002
CE02_manutentionnaire_001	2	manutentionnaire_Nom01_CE02	manutentionnaire	69902001	2025-12-17	actif	manutentionnaire_12-2025_001
CE02_manutentionnaire_002	2	manutentionnaire_Nom02_CE02	manutentionnaire	69902002	2025-12-16	actif	manutentionnaire_12-2025_002
LT01_manutentionnaire_001	3	manutentionnaire_Nom01_LT01	manutentionnaire	69903001	2025-12-17	actif	manutentionnaire_12-2025_001
LT01_manutentionnaire_002	3	manutentionnaire_Nom02_LT01	manutentionnaire	69903002	2025-12-16	actif	manutentionnaire_12-2025_002
LT02_manutentionnaire_001	4	manutentionnaire_Nom01_LT02	manutentionnaire	69904001	2025-12-17	actif	manutentionnaire_12-2025_001
LT02_manutentionnaire_002	4	manutentionnaire_Nom02_LT02	manutentionnaire	69904002	2025-12-16	actif	manutentionnaire_12-2025_002
NO01_manutentionnaire_001	5	manutentionnaire_Nom01_NO01	manutentionnaire	69905001	2025-12-17	actif	manutentionnaire_12-2025_001
NO01_manutentionnaire_002	5	manutentionnaire_Nom02_NO01	manutentionnaire	69905002	2025-12-16	actif	manutentionnaire_12-2025_002
NO02_manutentionnaire_001	6	manutentionnaire_Nom01_NO02	manutentionnaire	69906001	2025-12-17	actif	manutentionnaire_12-2025_001
NO02_manutentionnaire_002	6	manutentionnaire_Nom02_NO02	manutentionnaire	69906002	2025-12-16	actif	manutentionnaire_12-2025_002
EN01_manutentionnaire_001	7	manutentionnaire_Nom01_EN01	manutentionnaire	69907001	2025-12-17	actif	manutentionnaire_12-2025_001
EN01_manutentionnaire_002	7	manutentionnaire_Nom02_EN01	manutentionnaire	69907002	2025-12-16	actif	manutentionnaire_12-2025_002
EN02_manutentionnaire_001	8	manutentionnaire_Nom01_EN02	manutentionnaire	69908001	2025-12-17	actif	manutentionnaire_12-2025_001
EN02_manutentionnaire_002	8	manutentionnaire_Nom02_EN02	manutentionnaire	69908002	2025-12-16	actif	manutentionnaire_12-2025_002
AD01_manutentionnaire_001	9	manutentionnaire_Nom01_AD01	manutentionnaire	69909001	2025-12-17	actif	manutentionnaire_12-2025_001
AD01_manutentionnaire_002	9	manutentionnaire_Nom02_AD01	manutentionnaire	69909002	2025-12-16	actif	manutentionnaire_12-2025_002
AD02_manutentionnaire_001	10	manutentionnaire_Nom01_AD02	manutentionnaire	69910001	2025-12-17	actif	manutentionnaire_12-2025_001
AD02_manutentionnaire_002	10	manutentionnaire_Nom02_AD02	manutentionnaire	69910002	2025-12-16	actif	manutentionnaire_12-2025_002
ES01_manutentionnaire_001	11	manutentionnaire_Nom01_ES01	manutentionnaire	69911001	2025-12-17	actif	manutentionnaire_12-2025_001
ES01_manutentionnaire_002	11	manutentionnaire_Nom02_ES01	manutentionnaire	69911002	2025-12-16	actif	manutentionnaire_12-2025_002
ES02_manutentionnaire_001	12	manutentionnaire_Nom01_ES02	manutentionnaire	69912001	2025-12-17	actif	manutentionnaire_12-2025_001
ES02_manutentionnaire_002	12	manutentionnaire_Nom02_ES02	manutentionnaire	69912002	2025-12-16	actif	manutentionnaire_12-2025_002
OU01_manutentionnaire_001	13	manutentionnaire_Nom01_OU01	manutentionnaire	69913001	2025-12-17	actif	manutentionnaire_12-2025_001
OU01_manutentionnaire_002	13	manutentionnaire_Nom02_OU01	manutentionnaire	69913002	2025-12-16	actif	manutentionnaire_12-2025_002
OU02_manutentionnaire_001	14	manutentionnaire_Nom01_OU02	manutentionnaire	69914001	2025-12-17	actif	manutentionnaire_12-2025_001
OU02_manutentionnaire_002	14	manutentionnaire_Nom02_OU02	manutentionnaire	69914002	2025-12-16	actif	manutentionnaire_12-2025_002
SU01_manutentionnaire_001	15	manutentionnaire_Nom01_SU01	manutentionnaire	69915001	2025-12-17	actif	manutentionnaire_12-2025_001
SU01_manutentionnaire_002	15	manutentionnaire_Nom02_SU01	manutentionnaire	69915002	2025-12-16	actif	manutentionnaire_12-2025_002
SU02_manutentionnaire_001	16	manutentionnaire_Nom01_SU02	manutentionnaire	69916001	2025-12-17	actif	manutentionnaire_12-2025_001
SU02_manutentionnaire_002	16	manutentionnaire_Nom02_SU02	manutentionnaire	69916002	2025-12-16	actif	manutentionnaire_12-2025_002
NW01_manutentionnaire_001	17	manutentionnaire_Nom01_NW01	manutentionnaire	69917001	2025-12-17	actif	manutentionnaire_12-2025_001
NW01_manutentionnaire_002	17	manutentionnaire_Nom02_NW01	manutentionnaire	69917002	2025-12-16	actif	manutentionnaire_12-2025_002
NW02_manutentionnaire_001	18	manutentionnaire_Nom01_NW02	manutentionnaire	69918001	2025-12-17	actif	manutentionnaire_12-2025_001
NW02_manutentionnaire_002	18	manutentionnaire_Nom02_NW02	manutentionnaire	69918002	2025-12-16	actif	manutentionnaire_12-2025_002
SW01_manutentionnaire_001	19	manutentionnaire_Nom01_SW01	manutentionnaire	69919001	2025-12-17	actif	manutentionnaire_12-2025_001
SW01_manutentionnaire_002	19	manutentionnaire_Nom02_SW01	manutentionnaire	69919002	2025-12-16	actif	manutentionnaire_12-2025_002
SW02_manutentionnaire_001	20	manutentionnaire_Nom01_SW02	manutentionnaire	69920001	2025-12-17	actif	manutentionnaire_12-2025_001
SW02_manutentionnaire_002	20	manutentionnaire_Nom02_SW02	manutentionnaire	69920002	2025-12-16	actif	manutentionnaire_12-2025_002
CE01_securite_001	1	securite_Nom01_CE01	securite	69901001	2025-12-17	actif	securite_12-2025_001
CE01_securite_002	1	securite_Nom02_CE01	securite	69901002	2025-12-16	actif	securite_12-2025_002
CE02_securite_001	2	securite_Nom01_CE02	securite	69902001	2025-12-17	actif	securite_12-2025_001
CE02_securite_002	2	securite_Nom02_CE02	securite	69902002	2025-12-16	actif	securite_12-2025_002
LT01_securite_001	3	securite_Nom01_LT01	securite	69903001	2025-12-17	actif	securite_12-2025_001
LT01_securite_002	3	securite_Nom02_LT01	securite	69903002	2025-12-16	actif	securite_12-2025_002
LT02_securite_001	4	securite_Nom01_LT02	securite	69904001	2025-12-17	actif	securite_12-2025_001
LT02_securite_002	4	securite_Nom02_LT02	securite	69904002	2025-12-16	actif	securite_12-2025_002
NO01_securite_001	5	securite_Nom01_NO01	securite	69905001	2025-12-17	actif	securite_12-2025_001
NO01_securite_002	5	securite_Nom02_NO01	securite	69905002	2025-12-16	actif	securite_12-2025_002
NO02_securite_001	6	securite_Nom01_NO02	securite	69906001	2025-12-17	actif	securite_12-2025_001
NO02_securite_002	6	securite_Nom02_NO02	securite	69906002	2025-12-16	actif	securite_12-2025_002
EN01_securite_001	7	securite_Nom01_EN01	securite	69907001	2025-12-17	actif	securite_12-2025_001
EN01_securite_002	7	securite_Nom02_EN01	securite	69907002	2025-12-16	actif	securite_12-2025_002
EN02_securite_001	8	securite_Nom01_EN02	securite	69908001	2025-12-17	actif	securite_12-2025_001
EN02_securite_002	8	securite_Nom02_EN02	securite	69908002	2025-12-16	actif	securite_12-2025_002
AD01_securite_001	9	securite_Nom01_AD01	securite	69909001	2025-12-17	actif	securite_12-2025_001
AD01_securite_002	9	securite_Nom02_AD01	securite	69909002	2025-12-16	actif	securite_12-2025_002
AD02_securite_001	10	securite_Nom01_AD02	securite	69910001	2025-12-17	actif	securite_12-2025_001
AD02_securite_002	10	securite_Nom02_AD02	securite	69910002	2025-12-16	actif	securite_12-2025_002
ES01_securite_001	11	securite_Nom01_ES01	securite	69911001	2025-12-17	actif	securite_12-2025_001
ES01_securite_002	11	securite_Nom02_ES01	securite	69911002	2025-12-16	actif	securite_12-2025_002
ES02_securite_001	12	securite_Nom01_ES02	securite	69912001	2025-12-17	actif	securite_12-2025_001
ES02_securite_002	12	securite_Nom02_ES02	securite	69912002	2025-12-16	actif	securite_12-2025_002
OU01_securite_001	13	securite_Nom01_OU01	securite	69913001	2025-12-17	actif	securite_12-2025_001
OU01_securite_002	13	securite_Nom02_OU01	securite	69913002	2025-12-16	actif	securite_12-2025_002
OU02_securite_001	14	securite_Nom01_OU02	securite	69914001	2025-12-17	actif	securite_12-2025_001
OU02_securite_002	14	securite_Nom02_OU02	securite	69914002	2025-12-16	actif	securite_12-2025_002
SU01_securite_001	15	securite_Nom01_SU01	securite	69915001	2025-12-17	actif	securite_12-2025_001
SU01_securite_002	15	securite_Nom02_SU01	securite	69915002	2025-12-16	actif	securite_12-2025_002
SU02_securite_001	16	securite_Nom01_SU02	securite	69916001	2025-12-17	actif	securite_12-2025_001
SU02_securite_002	16	securite_Nom02_SU02	securite	69916002	2025-12-16	actif	securite_12-2025_002
NW01_securite_001	17	securite_Nom01_NW01	securite	69917001	2025-12-17	actif	securite_12-2025_001
NW01_securite_002	17	securite_Nom02_NW01	securite	69917002	2025-12-16	actif	securite_12-2025_002
NW02_securite_001	18	securite_Nom01_NW02	securite	69918001	2025-12-17	actif	securite_12-2025_001
NW02_securite_002	18	securite_Nom02_NW02	securite	69918002	2025-12-16	actif	securite_12-2025_002
SW01_securite_001	19	securite_Nom01_SW01	securite	69919001	2025-12-17	actif	securite_12-2025_001
SW01_securite_002	19	securite_Nom02_SW01	securite	69919002	2025-12-16	actif	securite_12-2025_002
SW02_securite_001	20	securite_Nom01_SW02	securite	69920001	2025-12-17	actif	securite_12-2025_001
SW02_securite_002	20	securite_Nom02_SW02	securite	69920002	2025-12-16	actif	securite_12-2025_002
CE01_chauffeur_001	1	chauffeur_Nom01_CE01	chauffeur	69901001	2025-12-17	actif	chauffeur_12-2025_001
CE01_chauffeur_002	1	chauffeur_Nom02_CE01	chauffeur	69901002	2025-12-16	actif	chauffeur_12-2025_002
CE02_chauffeur_001	2	chauffeur_Nom01_CE02	chauffeur	69902001	2025-12-17	actif	chauffeur_12-2025_001
CE02_chauffeur_002	2	chauffeur_Nom02_CE02	chauffeur	69902002	2025-12-16	actif	chauffeur_12-2025_002
LT01_chauffeur_001	3	chauffeur_Nom01_LT01	chauffeur	69903001	2025-12-17	actif	chauffeur_12-2025_001
LT01_chauffeur_002	3	chauffeur_Nom02_LT01	chauffeur	69903002	2025-12-16	actif	chauffeur_12-2025_002
LT02_chauffeur_001	4	chauffeur_Nom01_LT02	chauffeur	69904001	2025-12-17	actif	chauffeur_12-2025_001
LT02_chauffeur_002	4	chauffeur_Nom02_LT02	chauffeur	69904002	2025-12-16	actif	chauffeur_12-2025_002
NO01_chauffeur_001	5	chauffeur_Nom01_NO01	chauffeur	69905001	2025-12-17	actif	chauffeur_12-2025_001
NO01_chauffeur_002	5	chauffeur_Nom02_NO01	chauffeur	69905002	2025-12-16	actif	chauffeur_12-2025_002
NO02_chauffeur_001	6	chauffeur_Nom01_NO02	chauffeur	69906001	2025-12-17	actif	chauffeur_12-2025_001
NO02_chauffeur_002	6	chauffeur_Nom02_NO02	chauffeur	69906002	2025-12-16	actif	chauffeur_12-2025_002
EN01_chauffeur_001	7	chauffeur_Nom01_EN01	chauffeur	69907001	2025-12-17	actif	chauffeur_12-2025_001
EN01_chauffeur_002	7	chauffeur_Nom02_EN01	chauffeur	69907002	2025-12-16	actif	chauffeur_12-2025_002
EN02_chauffeur_001	8	chauffeur_Nom01_EN02	chauffeur	69908001	2025-12-17	actif	chauffeur_12-2025_001
EN02_chauffeur_002	8	chauffeur_Nom02_EN02	chauffeur	69908002	2025-12-16	actif	chauffeur_12-2025_002
AD01_chauffeur_001	9	chauffeur_Nom01_AD01	chauffeur	69909001	2025-12-17	actif	chauffeur_12-2025_001
AD01_chauffeur_002	9	chauffeur_Nom02_AD01	chauffeur	69909002	2025-12-16	actif	chauffeur_12-2025_002
AD02_chauffeur_001	10	chauffeur_Nom01_AD02	chauffeur	69910001	2025-12-17	actif	chauffeur_12-2025_001
AD02_chauffeur_002	10	chauffeur_Nom02_AD02	chauffeur	69910002	2025-12-16	actif	chauffeur_12-2025_002
ES01_chauffeur_001	11	chauffeur_Nom01_ES01	chauffeur	69911001	2025-12-17	actif	chauffeur_12-2025_001
ES01_chauffeur_002	11	chauffeur_Nom02_ES01	chauffeur	69911002	2025-12-16	actif	chauffeur_12-2025_002
ES02_chauffeur_001	12	chauffeur_Nom01_ES02	chauffeur	69912001	2025-12-17	actif	chauffeur_12-2025_001
ES02_chauffeur_002	12	chauffeur_Nom02_ES02	chauffeur	69912002	2025-12-16	actif	chauffeur_12-2025_002
OU01_chauffeur_001	13	chauffeur_Nom01_OU01	chauffeur	69913001	2025-12-17	actif	chauffeur_12-2025_001
OU01_chauffeur_002	13	chauffeur_Nom02_OU01	chauffeur	69913002	2025-12-16	actif	chauffeur_12-2025_002
OU02_chauffeur_001	14	chauffeur_Nom01_OU02	chauffeur	69914001	2025-12-17	actif	chauffeur_12-2025_001
OU02_chauffeur_002	14	chauffeur_Nom02_OU02	chauffeur	69914002	2025-12-16	actif	chauffeur_12-2025_002
SU01_chauffeur_001	15	chauffeur_Nom01_SU01	chauffeur	69915001	2025-12-17	actif	chauffeur_12-2025_001
SU01_chauffeur_002	15	chauffeur_Nom02_SU01	chauffeur	69915002	2025-12-16	actif	chauffeur_12-2025_002
SU02_chauffeur_001	16	chauffeur_Nom01_SU02	chauffeur	69916001	2025-12-17	actif	chauffeur_12-2025_001
SU02_chauffeur_002	16	chauffeur_Nom02_SU02	chauffeur	69916002	2025-12-16	actif	chauffeur_12-2025_002
NW01_chauffeur_001	17	chauffeur_Nom01_NW01	chauffeur	69917001	2025-12-17	actif	chauffeur_12-2025_001
NW01_chauffeur_002	17	chauffeur_Nom02_NW01	chauffeur	69917002	2025-12-16	actif	chauffeur_12-2025_002
NW02_chauffeur_001	18	chauffeur_Nom01_NW02	chauffeur	69918001	2025-12-17	actif	chauffeur_12-2025_001
NW02_chauffeur_002	18	chauffeur_Nom02_NW02	chauffeur	69918002	2025-12-16	actif	chauffeur_12-2025_002
SW01_chauffeur_001	19	chauffeur_Nom01_SW01	chauffeur	69919001	2025-12-17	actif	chauffeur_12-2025_001
SW01_chauffeur_002	19	chauffeur_Nom02_SW01	chauffeur	69919002	2025-12-16	actif	chauffeur_12-2025_002
SW02_chauffeur_001	20	chauffeur_Nom01_SW02	chauffeur	69920001	2025-12-17	actif	chauffeur_12-2025_001
SW02_chauffeur_002	20	chauffeur_Nom02_SW02	chauffeur	69920002	2025-12-16	actif	chauffeur_12-2025_002
CE01_caissier_001	1	caissier_Nom01_CE01	caissier	69901001	2025-12-17	actif	caissier_12-2025_001
CE01_caissier_002	1	caissier_Nom02_CE01	caissier	69901002	2025-12-16	actif	caissier_12-2025_002
CE02_caissier_001	2	caissier_Nom01_CE02	caissier	69902001	2025-12-17	actif	caissier_12-2025_001
CE02_caissier_002	2	caissier_Nom02_CE02	caissier	69902002	2025-12-16	actif	caissier_12-2025_002
LT01_caissier_001	3	caissier_Nom01_LT01	caissier	69903001	2025-12-17	actif	caissier_12-2025_001
LT01_caissier_002	3	caissier_Nom02_LT01	caissier	69903002	2025-12-16	actif	caissier_12-2025_002
LT02_caissier_001	4	caissier_Nom01_LT02	caissier	69904001	2025-12-17	actif	caissier_12-2025_001
LT02_caissier_002	4	caissier_Nom02_LT02	caissier	69904002	2025-12-16	actif	caissier_12-2025_002
NO01_caissier_001	5	caissier_Nom01_NO01	caissier	69905001	2025-12-17	actif	caissier_12-2025_001
NO01_caissier_002	5	caissier_Nom02_NO01	caissier	69905002	2025-12-16	actif	caissier_12-2025_002
NO02_caissier_001	6	caissier_Nom01_NO02	caissier	69906001	2025-12-17	actif	caissier_12-2025_001
NO02_caissier_002	6	caissier_Nom02_NO02	caissier	69906002	2025-12-16	actif	caissier_12-2025_002
EN01_caissier_001	7	caissier_Nom01_EN01	caissier	69907001	2025-12-17	actif	caissier_12-2025_001
EN01_caissier_002	7	caissier_Nom02_EN01	caissier	69907002	2025-12-16	actif	caissier_12-2025_002
EN02_caissier_001	8	caissier_Nom01_EN02	caissier	69908001	2025-12-17	actif	caissier_12-2025_001
EN02_caissier_002	8	caissier_Nom02_EN02	caissier	69908002	2025-12-16	actif	caissier_12-2025_002
AD01_caissier_001	9	caissier_Nom01_AD01	caissier	69909001	2025-12-17	actif	caissier_12-2025_001
AD01_caissier_002	9	caissier_Nom02_AD01	caissier	69909002	2025-12-16	actif	caissier_12-2025_002
AD02_caissier_001	10	caissier_Nom01_AD02	caissier	69910001	2025-12-17	actif	caissier_12-2025_001
AD02_caissier_002	10	caissier_Nom02_AD02	caissier	69910002	2025-12-16	actif	caissier_12-2025_002
ES01_caissier_001	11	caissier_Nom01_ES01	caissier	69911001	2025-12-17	actif	caissier_12-2025_001
ES01_caissier_002	11	caissier_Nom02_ES01	caissier	69911002	2025-12-16	actif	caissier_12-2025_002
ES02_caissier_001	12	caissier_Nom01_ES02	caissier	69912001	2025-12-17	actif	caissier_12-2025_001
ES02_caissier_002	12	caissier_Nom02_ES02	caissier	69912002	2025-12-16	actif	caissier_12-2025_002
OU01_caissier_001	13	caissier_Nom01_OU01	caissier	69913001	2025-12-17	actif	caissier_12-2025_001
OU01_caissier_002	13	caissier_Nom02_OU01	caissier	69913002	2025-12-16	actif	caissier_12-2025_002
OU02_caissier_001	14	caissier_Nom01_OU02	caissier	69914001	2025-12-17	actif	caissier_12-2025_001
OU02_caissier_002	14	caissier_Nom02_OU02	caissier	69914002	2025-12-16	actif	caissier_12-2025_002
SU01_caissier_001	15	caissier_Nom01_SU01	caissier	69915001	2025-12-17	actif	caissier_12-2025_001
SU01_caissier_002	15	caissier_Nom02_SU01	caissier	69915002	2025-12-16	actif	caissier_12-2025_002
SU02_caissier_001	16	caissier_Nom01_SU02	caissier	69916001	2025-12-17	actif	caissier_12-2025_001
SU02_caissier_002	16	caissier_Nom02_SU02	caissier	69916002	2025-12-16	actif	caissier_12-2025_002
NW01_caissier_001	17	caissier_Nom01_NW01	caissier	69917001	2025-12-17	actif	caissier_12-2025_001
NW01_caissier_002	17	caissier_Nom02_NW01	caissier	69917002	2025-12-16	actif	caissier_12-2025_002
NW02_caissier_001	18	caissier_Nom01_NW02	caissier	69918001	2025-12-17	actif	caissier_12-2025_001
NW02_caissier_002	18	caissier_Nom02_NW02	caissier	69918002	2025-12-16	actif	caissier_12-2025_002
SW01_caissier_001	19	caissier_Nom01_SW01	caissier	69919001	2025-12-17	actif	caissier_12-2025_001
SW01_caissier_002	19	caissier_Nom02_SW01	caissier	69919002	2025-12-16	actif	caissier_12-2025_002
SW02_caissier_001	20	caissier_Nom01_SW02	caissier	69920001	2025-12-17	actif	caissier_12-2025_001
SW02_caissier_002	20	caissier_Nom02_SW02	caissier	69920002	2025-12-16	actif	caissier_12-2025_002
CE01_magasinier_001	1	magasinier_Nom01_CE01	magasinier	69901001	2025-12-17	actif	magasinier_12-2025_001
CE01_magasinier_002	1	magasinier_Nom02_CE01	magasinier	69901002	2025-12-16	actif	magasinier_12-2025_002
CE02_magasinier_001	2	magasinier_Nom01_CE02	magasinier	69902001	2025-12-17	actif	magasinier_12-2025_001
CE02_magasinier_002	2	magasinier_Nom02_CE02	magasinier	69902002	2025-12-16	actif	magasinier_12-2025_002
LT01_magasinier_001	3	magasinier_Nom01_LT01	magasinier	69903001	2025-12-17	actif	magasinier_12-2025_001
LT01_magasinier_002	3	magasinier_Nom02_LT01	magasinier	69903002	2025-12-16	actif	magasinier_12-2025_002
LT02_magasinier_001	4	magasinier_Nom01_LT02	magasinier	69904001	2025-12-17	actif	magasinier_12-2025_001
LT02_magasinier_002	4	magasinier_Nom02_LT02	magasinier	69904002	2025-12-16	actif	magasinier_12-2025_002
NO01_magasinier_001	5	magasinier_Nom01_NO01	magasinier	69905001	2025-12-17	actif	magasinier_12-2025_001
NO01_magasinier_002	5	magasinier_Nom02_NO01	magasinier	69905002	2025-12-16	actif	magasinier_12-2025_002
NO02_magasinier_001	6	magasinier_Nom01_NO02	magasinier	69906001	2025-12-17	actif	magasinier_12-2025_001
NO02_magasinier_002	6	magasinier_Nom02_NO02	magasinier	69906002	2025-12-16	actif	magasinier_12-2025_002
EN01_magasinier_001	7	magasinier_Nom01_EN01	magasinier	69907001	2025-12-17	actif	magasinier_12-2025_001
EN01_magasinier_002	7	magasinier_Nom02_EN01	magasinier	69907002	2025-12-16	actif	magasinier_12-2025_002
EN02_magasinier_001	8	magasinier_Nom01_EN02	magasinier	69908001	2025-12-17	actif	magasinier_12-2025_001
EN02_magasinier_002	8	magasinier_Nom02_EN02	magasinier	69908002	2025-12-16	actif	magasinier_12-2025_002
AD01_magasinier_001	9	magasinier_Nom01_AD01	magasinier	69909001	2025-12-17	actif	magasinier_12-2025_001
AD01_magasinier_002	9	magasinier_Nom02_AD01	magasinier	69909002	2025-12-16	actif	magasinier_12-2025_002
AD02_magasinier_001	10	magasinier_Nom01_AD02	magasinier	69910001	2025-12-17	actif	magasinier_12-2025_001
AD02_magasinier_002	10	magasinier_Nom02_AD02	magasinier	69910002	2025-12-16	actif	magasinier_12-2025_002
ES01_magasinier_001	11	magasinier_Nom01_ES01	magasinier	69911001	2025-12-17	actif	magasinier_12-2025_001
ES01_magasinier_002	11	magasinier_Nom02_ES01	magasinier	69911002	2025-12-16	actif	magasinier_12-2025_002
ES02_magasinier_001	12	magasinier_Nom01_ES02	magasinier	69912001	2025-12-17	actif	magasinier_12-2025_001
ES02_magasinier_002	12	magasinier_Nom02_ES02	magasinier	69912002	2025-12-16	actif	magasinier_12-2025_002
OU01_magasinier_001	13	magasinier_Nom01_OU01	magasinier	69913001	2025-12-17	actif	magasinier_12-2025_001
OU01_magasinier_002	13	magasinier_Nom02_OU01	magasinier	69913002	2025-12-16	actif	magasinier_12-2025_002
OU02_magasinier_001	14	magasinier_Nom01_OU02	magasinier	69914001	2025-12-17	actif	magasinier_12-2025_001
OU02_magasinier_002	14	magasinier_Nom02_OU02	magasinier	69914002	2025-12-16	actif	magasinier_12-2025_002
SU01_magasinier_001	15	magasinier_Nom01_SU01	magasinier	69915001	2025-12-17	actif	magasinier_12-2025_001
SU01_magasinier_002	15	magasinier_Nom02_SU01	magasinier	69915002	2025-12-16	actif	magasinier_12-2025_002
SU02_magasinier_001	16	magasinier_Nom01_SU02	magasinier	69916001	2025-12-17	actif	magasinier_12-2025_001
SU02_magasinier_002	16	magasinier_Nom02_SU02	magasinier	69916002	2025-12-16	actif	magasinier_12-2025_002
NW01_magasinier_001	17	magasinier_Nom01_NW01	magasinier	69917001	2025-12-17	actif	magasinier_12-2025_001
NW01_magasinier_002	17	magasinier_Nom02_NW01	magasinier	69917002	2025-12-16	actif	magasinier_12-2025_002
NW02_magasinier_001	18	magasinier_Nom01_NW02	magasinier	69918001	2025-12-17	actif	magasinier_12-2025_001
NW02_magasinier_002	18	magasinier_Nom02_NW02	magasinier	69918002	2025-12-16	actif	magasinier_12-2025_002
SW01_magasinier_001	19	magasinier_Nom01_SW01	magasinier	69919001	2025-12-17	actif	magasinier_12-2025_001
SW01_magasinier_002	19	magasinier_Nom02_SW01	magasinier	69919002	2025-12-16	actif	magasinier_12-2025_002
SW02_magasinier_001	20	magasinier_Nom01_SW02	magasinier	69920001	2025-12-17	actif	magasinier_12-2025_001
SW02_magasinier_002	20	magasinier_Nom02_SW02	magasinier	69920002	2025-12-16	actif	magasinier_12-2025_002
CE01_maintenance_001	1	maintenance_Nom01_CE01	maintenance	69901001	2025-12-17	actif	maintenance_12-2025_001
CE01_maintenance_002	1	maintenance_Nom02_CE01	maintenance	69901002	2025-12-16	actif	maintenance_12-2025_002
CE02_maintenance_001	2	maintenance_Nom01_CE02	maintenance	69902001	2025-12-17	actif	maintenance_12-2025_001
CE02_maintenance_002	2	maintenance_Nom02_CE02	maintenance	69902002	2025-12-16	actif	maintenance_12-2025_002
LT01_maintenance_001	3	maintenance_Nom01_LT01	maintenance	69903001	2025-12-17	actif	maintenance_12-2025_001
LT01_maintenance_002	3	maintenance_Nom02_LT01	maintenance	69903002	2025-12-16	actif	maintenance_12-2025_002
LT02_maintenance_001	4	maintenance_Nom01_LT02	maintenance	69904001	2025-12-17	actif	maintenance_12-2025_001
LT02_maintenance_002	4	maintenance_Nom02_LT02	maintenance	69904002	2025-12-16	actif	maintenance_12-2025_002
NO01_maintenance_001	5	maintenance_Nom01_NO01	maintenance	69905001	2025-12-17	actif	maintenance_12-2025_001
NO01_maintenance_002	5	maintenance_Nom02_NO01	maintenance	69905002	2025-12-16	actif	maintenance_12-2025_002
NO02_maintenance_001	6	maintenance_Nom01_NO02	maintenance	69906001	2025-12-17	actif	maintenance_12-2025_001
NO02_maintenance_002	6	maintenance_Nom02_NO02	maintenance	69906002	2025-12-16	actif	maintenance_12-2025_002
EN01_maintenance_001	7	maintenance_Nom01_EN01	maintenance	69907001	2025-12-17	actif	maintenance_12-2025_001
EN01_maintenance_002	7	maintenance_Nom02_EN01	maintenance	69907002	2025-12-16	actif	maintenance_12-2025_002
EN02_maintenance_001	8	maintenance_Nom01_EN02	maintenance	69908001	2025-12-17	actif	maintenance_12-2025_001
EN02_maintenance_002	8	maintenance_Nom02_EN02	maintenance	69908002	2025-12-16	actif	maintenance_12-2025_002
AD01_maintenance_001	9	maintenance_Nom01_AD01	maintenance	69909001	2025-12-17	actif	maintenance_12-2025_001
AD01_maintenance_002	9	maintenance_Nom02_AD01	maintenance	69909002	2025-12-16	actif	maintenance_12-2025_002
AD02_maintenance_001	10	maintenance_Nom01_AD02	maintenance	69910001	2025-12-17	actif	maintenance_12-2025_001
AD02_maintenance_002	10	maintenance_Nom02_AD02	maintenance	69910002	2025-12-16	actif	maintenance_12-2025_002
ES01_maintenance_001	11	maintenance_Nom01_ES01	maintenance	69911001	2025-12-17	actif	maintenance_12-2025_001
ES01_maintenance_002	11	maintenance_Nom02_ES01	maintenance	69911002	2025-12-16	actif	maintenance_12-2025_002
ES02_maintenance_001	12	maintenance_Nom01_ES02	maintenance	69912001	2025-12-17	actif	maintenance_12-2025_001
ES02_maintenance_002	12	maintenance_Nom02_ES02	maintenance	69912002	2025-12-16	actif	maintenance_12-2025_002
OU01_maintenance_001	13	maintenance_Nom01_OU01	maintenance	69913001	2025-12-17	actif	maintenance_12-2025_001
OU01_maintenance_002	13	maintenance_Nom02_OU01	maintenance	69913002	2025-12-16	actif	maintenance_12-2025_002
OU02_maintenance_001	14	maintenance_Nom01_OU02	maintenance	69914001	2025-12-17	actif	maintenance_12-2025_001
OU02_maintenance_002	14	maintenance_Nom02_OU02	maintenance	69914002	2025-12-16	actif	maintenance_12-2025_002
SU01_maintenance_001	15	maintenance_Nom01_SU01	maintenance	69915001	2025-12-17	actif	maintenance_12-2025_001
SU01_maintenance_002	15	maintenance_Nom02_SU01	maintenance	69915002	2025-12-16	actif	maintenance_12-2025_002
SU02_maintenance_001	16	maintenance_Nom01_SU02	maintenance	69916001	2025-12-17	actif	maintenance_12-2025_001
SU02_maintenance_002	16	maintenance_Nom02_SU02	maintenance	69916002	2025-12-16	actif	maintenance_12-2025_002
NW01_maintenance_001	17	maintenance_Nom01_NW01	maintenance	69917001	2025-12-17	actif	maintenance_12-2025_001
NW01_maintenance_002	17	maintenance_Nom02_NW01	maintenance	69917002	2025-12-16	actif	maintenance_12-2025_002
NW02_maintenance_001	18	maintenance_Nom01_NW02	maintenance	69918001	2025-12-17	actif	maintenance_12-2025_001
NW02_maintenance_002	18	maintenance_Nom02_NW02	maintenance	69918002	2025-12-16	actif	maintenance_12-2025_002
SW01_maintenance_001	19	maintenance_Nom01_SW01	maintenance	69919001	2025-12-17	actif	maintenance_12-2025_001
SW01_maintenance_002	19	maintenance_Nom02_SW01	maintenance	69919002	2025-12-16	actif	maintenance_12-2025_002
SW02_maintenance_001	20	maintenance_Nom01_SW02	maintenance	69920001	2025-12-17	actif	maintenance_12-2025_001
SW02_maintenance_002	20	maintenance_Nom02_SW02	maintenance	69920002	2025-12-16	actif	maintenance_12-2025_002
CE01_nettoyage_001	1	nettoyage_Nom01_CE01	nettoyage	69901001	2025-12-17	actif	nettoyage_12-2025_001
CE01_nettoyage_002	1	nettoyage_Nom02_CE01	nettoyage	69901002	2025-12-16	actif	nettoyage_12-2025_002
CE02_nettoyage_001	2	nettoyage_Nom01_CE02	nettoyage	69902001	2025-12-17	actif	nettoyage_12-2025_001
CE02_nettoyage_002	2	nettoyage_Nom02_CE02	nettoyage	69902002	2025-12-16	actif	nettoyage_12-2025_002
LT01_nettoyage_001	3	nettoyage_Nom01_LT01	nettoyage	69903001	2025-12-17	actif	nettoyage_12-2025_001
LT01_nettoyage_002	3	nettoyage_Nom02_LT01	nettoyage	69903002	2025-12-16	actif	nettoyage_12-2025_002
LT02_nettoyage_001	4	nettoyage_Nom01_LT02	nettoyage	69904001	2025-12-17	actif	nettoyage_12-2025_001
LT02_nettoyage_002	4	nettoyage_Nom02_LT02	nettoyage	69904002	2025-12-16	actif	nettoyage_12-2025_002
NO01_nettoyage_001	5	nettoyage_Nom01_NO01	nettoyage	69905001	2025-12-17	actif	nettoyage_12-2025_001
NO01_nettoyage_002	5	nettoyage_Nom02_NO01	nettoyage	69905002	2025-12-16	actif	nettoyage_12-2025_002
NO02_nettoyage_001	6	nettoyage_Nom01_NO02	nettoyage	69906001	2025-12-17	actif	nettoyage_12-2025_001
NO02_nettoyage_002	6	nettoyage_Nom02_NO02	nettoyage	69906002	2025-12-16	actif	nettoyage_12-2025_002
EN01_nettoyage_001	7	nettoyage_Nom01_EN01	nettoyage	69907001	2025-12-17	actif	nettoyage_12-2025_001
EN01_nettoyage_002	7	nettoyage_Nom02_EN01	nettoyage	69907002	2025-12-16	actif	nettoyage_12-2025_002
EN02_nettoyage_001	8	nettoyage_Nom01_EN02	nettoyage	69908001	2025-12-17	actif	nettoyage_12-2025_001
EN02_nettoyage_002	8	nettoyage_Nom02_EN02	nettoyage	69908002	2025-12-16	actif	nettoyage_12-2025_002
AD01_nettoyage_001	9	nettoyage_Nom01_AD01	nettoyage	69909001	2025-12-17	actif	nettoyage_12-2025_001
AD01_nettoyage_002	9	nettoyage_Nom02_AD01	nettoyage	69909002	2025-12-16	actif	nettoyage_12-2025_002
AD02_nettoyage_001	10	nettoyage_Nom01_AD02	nettoyage	69910001	2025-12-17	actif	nettoyage_12-2025_001
AD02_nettoyage_002	10	nettoyage_Nom02_AD02	nettoyage	69910002	2025-12-16	actif	nettoyage_12-2025_002
ES01_nettoyage_001	11	nettoyage_Nom01_ES01	nettoyage	69911001	2025-12-17	actif	nettoyage_12-2025_001
ES01_nettoyage_002	11	nettoyage_Nom02_ES01	nettoyage	69911002	2025-12-16	actif	nettoyage_12-2025_002
ES02_nettoyage_001	12	nettoyage_Nom01_ES02	nettoyage	69912001	2025-12-17	actif	nettoyage_12-2025_001
ES02_nettoyage_002	12	nettoyage_Nom02_ES02	nettoyage	69912002	2025-12-16	actif	nettoyage_12-2025_002
OU01_nettoyage_001	13	nettoyage_Nom01_OU01	nettoyage	69913001	2025-12-17	actif	nettoyage_12-2025_001
OU01_nettoyage_002	13	nettoyage_Nom02_OU01	nettoyage	69913002	2025-12-16	actif	nettoyage_12-2025_002
OU02_nettoyage_001	14	nettoyage_Nom01_OU02	nettoyage	69914001	2025-12-17	actif	nettoyage_12-2025_001
OU02_nettoyage_002	14	nettoyage_Nom02_OU02	nettoyage	69914002	2025-12-16	actif	nettoyage_12-2025_002
SU01_nettoyage_001	15	nettoyage_Nom01_SU01	nettoyage	69915001	2025-12-17	actif	nettoyage_12-2025_001
SU01_nettoyage_002	15	nettoyage_Nom02_SU01	nettoyage	69915002	2025-12-16	actif	nettoyage_12-2025_002
SU02_nettoyage_001	16	nettoyage_Nom01_SU02	nettoyage	69916001	2025-12-17	actif	nettoyage_12-2025_001
SU02_nettoyage_002	16	nettoyage_Nom02_SU02	nettoyage	69916002	2025-12-16	actif	nettoyage_12-2025_002
NW01_nettoyage_001	17	nettoyage_Nom01_NW01	nettoyage	69917001	2025-12-17	actif	nettoyage_12-2025_001
NW01_nettoyage_002	17	nettoyage_Nom02_NW01	nettoyage	69917002	2025-12-16	actif	nettoyage_12-2025_002
NW02_nettoyage_001	18	nettoyage_Nom01_NW02	nettoyage	69918001	2025-12-17	actif	nettoyage_12-2025_001
NW02_nettoyage_002	18	nettoyage_Nom02_NW02	nettoyage	69918002	2025-12-16	actif	nettoyage_12-2025_002
SW01_nettoyage_001	19	nettoyage_Nom01_SW01	nettoyage	69919001	2025-12-17	actif	nettoyage_12-2025_001
SW01_nettoyage_002	19	nettoyage_Nom02_SW01	nettoyage	69919002	2025-12-16	actif	nettoyage_12-2025_002
SW02_nettoyage_001	20	nettoyage_Nom01_SW02	nettoyage	69920001	2025-12-17	actif	nettoyage_12-2025_001
SW02_nettoyage_002	20	nettoyage_Nom02_SW02	nettoyage	69920002	2025-12-16	actif	nettoyage_12-2025_002
CE01_logistique_001	1	logistique_Nom01_CE01	logistique	69901001	2025-12-17	actif	logistique_12-2025_001
CE01_logistique_002	1	logistique_Nom02_CE01	logistique	69901002	2025-12-16	actif	logistique_12-2025_002
CE02_logistique_001	2	logistique_Nom01_CE02	logistique	69902001	2025-12-17	actif	logistique_12-2025_001
CE02_logistique_002	2	logistique_Nom02_CE02	logistique	69902002	2025-12-16	actif	logistique_12-2025_002
LT01_logistique_001	3	logistique_Nom01_LT01	logistique	69903001	2025-12-17	actif	logistique_12-2025_001
LT01_logistique_002	3	logistique_Nom02_LT01	logistique	69903002	2025-12-16	actif	logistique_12-2025_002
LT02_logistique_001	4	logistique_Nom01_LT02	logistique	69904001	2025-12-17	actif	logistique_12-2025_001
LT02_logistique_002	4	logistique_Nom02_LT02	logistique	69904002	2025-12-16	actif	logistique_12-2025_002
NO01_logistique_001	5	logistique_Nom01_NO01	logistique	69905001	2025-12-17	actif	logistique_12-2025_001
NO01_logistique_002	5	logistique_Nom02_NO01	logistique	69905002	2025-12-16	actif	logistique_12-2025_002
NO02_logistique_001	6	logistique_Nom01_NO02	logistique	69906001	2025-12-17	actif	logistique_12-2025_001
NO02_logistique_002	6	logistique_Nom02_NO02	logistique	69906002	2025-12-16	actif	logistique_12-2025_002
EN01_logistique_001	7	logistique_Nom01_EN01	logistique	69907001	2025-12-17	actif	logistique_12-2025_001
EN01_logistique_002	7	logistique_Nom02_EN01	logistique	69907002	2025-12-16	actif	logistique_12-2025_002
EN02_logistique_001	8	logistique_Nom01_EN02	logistique	69908001	2025-12-17	actif	logistique_12-2025_001
EN02_logistique_002	8	logistique_Nom02_EN02	logistique	69908002	2025-12-16	actif	logistique_12-2025_002
AD01_logistique_001	9	logistique_Nom01_AD01	logistique	69909001	2025-12-17	actif	logistique_12-2025_001
AD01_logistique_002	9	logistique_Nom02_AD01	logistique	69909002	2025-12-16	actif	logistique_12-2025_002
AD02_logistique_001	10	logistique_Nom01_AD02	logistique	69910001	2025-12-17	actif	logistique_12-2025_001
AD02_logistique_002	10	logistique_Nom02_AD02	logistique	69910002	2025-12-16	actif	logistique_12-2025_002
ES01_logistique_001	11	logistique_Nom01_ES01	logistique	69911001	2025-12-17	actif	logistique_12-2025_001
ES01_logistique_002	11	logistique_Nom02_ES01	logistique	69911002	2025-12-16	actif	logistique_12-2025_002
ES02_logistique_001	12	logistique_Nom01_ES02	logistique	69912001	2025-12-17	actif	logistique_12-2025_001
ES02_logistique_002	12	logistique_Nom02_ES02	logistique	69912002	2025-12-16	actif	logistique_12-2025_002
OU01_logistique_001	13	logistique_Nom01_OU01	logistique	69913001	2025-12-17	actif	logistique_12-2025_001
OU01_logistique_002	13	logistique_Nom02_OU01	logistique	69913002	2025-12-16	actif	logistique_12-2025_002
OU02_logistique_001	14	logistique_Nom01_OU02	logistique	69914001	2025-12-17	actif	logistique_12-2025_001
OU02_logistique_002	14	logistique_Nom02_OU02	logistique	69914002	2025-12-16	actif	logistique_12-2025_002
SU01_logistique_001	15	logistique_Nom01_SU01	logistique	69915001	2025-12-17	actif	logistique_12-2025_001
SU01_logistique_002	15	logistique_Nom02_SU01	logistique	69915002	2025-12-16	actif	logistique_12-2025_002
SU02_logistique_001	16	logistique_Nom01_SU02	logistique	69916001	2025-12-17	actif	logistique_12-2025_001
SU02_logistique_002	16	logistique_Nom02_SU02	logistique	69916002	2025-12-16	actif	logistique_12-2025_002
NW01_logistique_001	17	logistique_Nom01_NW01	logistique	69917001	2025-12-17	actif	logistique_12-2025_001
NW01_logistique_002	17	logistique_Nom02_NW01	logistique	69917002	2025-12-16	actif	logistique_12-2025_002
NW02_logistique_001	18	logistique_Nom01_NW02	logistique	69918001	2025-12-17	actif	logistique_12-2025_001
NW02_logistique_002	18	logistique_Nom02_NW02	logistique	69918002	2025-12-16	actif	logistique_12-2025_002
SW01_logistique_001	19	logistique_Nom01_SW01	logistique	69919001	2025-12-17	actif	logistique_12-2025_001
SW01_logistique_002	19	logistique_Nom02_SW01	logistique	69919002	2025-12-16	actif	logistique_12-2025_002
SW02_logistique_001	20	logistique_Nom01_SW02	logistique	69920001	2025-12-17	actif	logistique_12-2025_001
SW02_logistique_002	20	logistique_Nom02_SW02	logistique	69920002	2025-12-16	actif	logistique_12-2025_002
CE01_magasinier_003	1	Don Papy	magasinier	699989796	2025-12-24	actif	magasinier_12-2025_003
\.


--
-- Data for Name: internal_bank_logs; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."internal_bank_logs" ("id", "type_mouvement", "lot_id", "admission_id", "montant_realise", "prix_acquisition_total", "prix_sortie_total", "difference_valeur", "date_operation", "utilisateur") FROM stdin;
1	RETRAIT_CLIENT	5	10	300.00	2500.00	2500.00	0.00	2025-12-22 13:28:56.282676	superadmin
8	RETRAIT_CLIENT	5	\N	\N	\N	\N	0.00	2026-01-14 22:59:17.978623	superadmin
17	RETRAIT_CLIENT	15	\N	\N	\N	\N	0.00	2026-01-15 00:23:13.623802	superadmin
18	RETRAIT_CLIENT	18	\N	\N	\N	\N	0.00	2026-01-15 00:23:39.322109	superadmin
19	RETRAIT_CLIENT	10	\N	\N	\N	\N	0.00	2026-01-16 16:42:55.034217	ndjomfils
20	RETRAIT_CLIENT	10	\N	\N	\N	\N	0.00	2026-01-16 16:42:55.159872	ndjomfils
21	RETRAIT_CLIENT	15	\N	\N	\N	\N	0.00	2026-01-18 11:53:22.459853	superadmin
22	RETRAIT_MAGASIN	5	\N	\N	\N	\N	0.00	2026-01-18 13:27:11.838263	superadmin
23	RETRAIT_MAGASIN	15	\N	\N	\N	\N	0.00	2026-01-23 01:18:55.687236	superadmin
24	RETRAIT_CLIENT	17	\N	\N	\N	\N	0.00	2026-01-27 22:32:31.180985	superadmin
25	RETRAIT_CLIENT	6	\N	\N	\N	\N	0.00	2026-01-27 22:32:57.597583	superadmin
\.


--
-- Data for Name: logs_deploiement; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."logs_deploiement" ("id", "date_erreur", "contexte", "utilisateur", "role_utilisateur", "message_erreur", "etat_formulaire", "resolu") FROM stdin;
\.


--
-- Data for Name: lots; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."lots" ("id", "description", "categorie", "date_creation", "criteres_admission", "unites_admises", "prix_ref", "stock_disponible", "valeur_estimee_stock", "notes") FROM stdin;
2	Paniers en rotin 40x16	nonalim	2025-12-21 21:43:53.062915	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	0.00	0.00	\N
3	Paniers en rotin 40x16	nonalim	2025-12-21 21:43:53.568168	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	0.00	0.00	\N
4	Paniers en rotin 40x16	nonalim	2025-12-21 21:44:41.473721	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	0.00	0.00	\N
7	Paniers en rotin 40x16	nonalim	2025-12-21 22:01:27.43939	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	0.00	0.00	\N
8	Papayes solo	court	2025-12-21 22:02:38.416725	["Date récente", "Durée ≤ 7 jours", "Chaîne de froid", "Emballage adapté"]	["kg", "unite"]	2500.00	0.00	0.00	\N
11	Oranges	frais	2025-12-21 22:04:45.852324	["Fraîcheur", "Calibre minimum", "Absence de pesticides", "Présentation propre"]	["kg"]	2500.00	0.00	0.00	\N
12	Tomates de Mandoga	court	2025-12-21 22:41:43.971184	["Date récente", "Durée ≤ 7 jours", "Chaîne de froid", "Emballage adapté"]	["kg"]	650.00	0.00	0.00	\N
13	Tomates de Mandoga	court	2025-12-21 22:41:44.389783	["Date récente", "Durée ≤ 7 jours", "Chaîne de froid", "Emballage adapté"]	["kg"]	650.00	0.00	0.00	\N
18	Verre importés	sensibles	2025-12-28 00:29:27.902337	[{"type": "standard", "critere": "Chaîne du froid intacte", "obligatoire": true}, {"type": "standard", "critere": "Traçabilité origine", "obligatoire": true}, {"type": "standard", "critere": "Emballage hermétique", "obligatoire": true}]	["unites"]	4500.00	-4000.00	0.00	Conserver dans un lieu sécurisé
6	Paniers en rotin 40x16	nonalim	2025-12-21 22:01:27.016356	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	-3200.00	0.00	\N
10	Oranges	frais	2025-12-21 22:04:45.067778	["Fraîcheur", "Calibre minimum", "Absence de pesticides", "Présentation propre"]	["kg"]	2500.00	-50.00	0.00	\N
5	Paniers en rotin 40x16	nonalim	2025-12-21 21:44:41.978202	["Finition correcte", "Solidité", "Esthétique", "Traçabilité"]	["kg", "g"]	5000.00	339.00	100000.00	\N
9	Papayes solo	court	2025-12-21 22:02:38.853741	["Date récente", "Durée ≤ 7 jours", "Chaîne de froid", "Emballage adapté"]	["kg", "unite"]	2500.00	10.00	6000.00	\N
14	Miondonini	manufactures_alim	2025-12-26 17:09:46.454785	[{"type": "standard", "critere": "Emballage intact/non gonflé", "obligatoire": true}, {"type": "standard", "critere": "Date péremption valide", "obligatoire": true}, {"type": "standard", "critere": "Étiquetage conforme (ANOR)", "obligatoire": true}, {"type": "standard", "critere": "Numéro de lot présent", "obligatoire": true}]	["kg"]	500.00	0.00	0.00	Vous vous assurerez de vérifier les critères d'admissibilité.
15	Huile de palme de Mayos	huiles_liquides	2025-12-27 13:52:26.638099	[{"type": "standard", "critere": "Scellé de sécurité intact", "obligatoire": true}, {"type": "standard", "critere": "Limpidité (pas de dépôt)", "obligatoire": true}, {"type": "standard", "critere": "Absence de fuite", "obligatoire": true}, {"type": "standard", "critere": "DLC visible", "obligatoire": true}, {"type": "standard", "critere": "Couleur naturelle", "obligatoire": true}]	["litres"]	1400.00	-645.00	0.00	Conserver dans un endroit fais et sec
17	Manioc jaune de Minkama	frais	2025-12-27 13:54:36.821612	[{"type": "standard", "critere": "Vivacité/Fraîcheur visuelle", "obligatoire": true}, {"type": "standard", "critere": "Absence de pourriture", "obligatoire": true}, {"type": "standard", "critere": "Absence insectes/parasites", "obligatoire": true}, {"type": "standard", "critere": "Calibrage homogène", "obligatoire": true}, {"type": "standard", "critere": "Date récolte < 48h", "obligatoire": true}]	["sacs"]	17850.00	-25.00	0.00	Conservation en milieu repoduisant les conditions naturelles
16	Poivre de Song Ndong	secs	2025-12-27 13:53:04.703492	[{"type": "standard", "critere": "Humidité < 12% (Test manuel)", "obligatoire": true}, {"type": "standard", "critere": "Absence de charançons", "obligatoire": true}, {"type": "standard", "critere": "Grains entiers/non brisés", "obligatoire": true}, {"type": "standard", "critere": "Odeur saine (pas de moisi)", "obligatoire": true}, {"type": "standard", "critere": "Absence de cailloux", "obligatoire": true}]	["litres"]	5000.00	0.00	0.00	Aucune
\.


--
-- Data for Name: lots_traces; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."lots_traces" ("id", "admission_id", "lot_id", "magasin_id", "quantite_initiale", "quantite_restante", "date_reception", "date_expiration", "numero_lot", "statut") FROM stdin;
\.


--
-- Data for Name: magasins; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."magasins" ("id", "nom", "region_id", "code") FROM stdin;
1	Centre A	1	CE01
2	Centre B	1	CE02
3	Littoral A	2	LT01
4	Littoral B	2	LT02
5	Nord A	3	NO01
6	Nord B	3	NO02
7	ExtrÃªme-Nord A	4	EN01
8	ExtrÃªme-Nord B	4	EN02
9	Adamaoua A	5	AD01
10	Adamaoua B	5	AD02
11	Est A	6	ES01
12	Est B	6	ES02
13	Ouest A	7	OU01
14	Ouest B	7	OU02
15	Sud A	8	SU01
16	Sud B	8	SU02
17	Nord-Ouest A	9	NW01
18	Nord-Ouest B	9	NW02
19	Sud-Ouest A	10	SW01
20	Sud-Ouest B	10	SW02
21	Entrepôt Central	\N	CE00
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."messages" ("id", "expediteur_id", "destinataire_id", "expediteur", "objet", "contenu", "date", "lu", "type_notification") FROM stdin;
\.


--
-- Data for Name: operations; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."operations" ("id", "utilisateur", "type_operation", "montant", "solde_apres", "date_operation") FROM stdin;
\.


--
-- Data for Name: operations_caisse; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."operations_caisse" ("id", "utilisateur", "type_operation", "montant", "solde_apres", "producteur", "description", "date_operation", "caisse_id", "lot_id", "producteur_id") FROM stdin;
\.


--
-- Data for Name: producteurs; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."producteurs" ("id", "nom_producteur", "tel_producteur", "type_producteur", "carte_membre", "points_fidelite", "solde", "statut", "region_id", "departement_id", "arrondissement_id", "localite", "matricule", "date_integration") FROM stdin;
1	artisan_Prod_Ngaoundal	699001	artisan	f	0	0.00	en_attente	5	1	1	LocalitÃ© Ngaoundal	artisan_12-2025_001	2025-12-18
2	coopÃ©rative_Prod_Tibati	699002	coopÃ©rative	f	0	0.00	en_attente	5	1	2	LocalitÃ© Tibati	coop_12-2025_001	2025-12-18
3	agriculteur_Prod_Galim-TignÃ¨re	699003	agriculteur	f	0	0.00	en_attente	5	2	3	LocalitÃ© Galim-TignÃ¨re	agri_12-2025_001	2025-12-18
4	alimentaire manufacture_Prod_Kontcha	699004	alimentaire manufacture	f	0	0.00	en_attente	5	2	4	LocalitÃ© Kontcha	alim_12-2025_001	2025-12-18
5	individuel_Prod_Mayo-BalÃ©o	699005	individuel	f	0	0.00	en_attente	5	2	5	LocalitÃ© Mayo-BalÃ©o	indiv_12-2025_001	2025-12-18
6	autre_Prod_TignÃ¨re	699006	autre	f	0	0.00	en_attente	5	2	6	LocalitÃ© TignÃ¨re	autre_12-2025_001	2025-12-18
7	autre_Prod_Bankim	699007	autre	f	0	0.00	en_attente	5	3	7	LocalitÃ© Bankim	autre_12-2025_001	2025-12-18
8	coopÃ©rative_Prod_Banyo	699008	coopÃ©rative	f	0	0.00	en_attente	5	3	8	LocalitÃ© Banyo	coop_12-2025_001	2025-12-18
9	Ã©leveur_Prod_Mayo-DarlÃ©	699009	Ã©leveur	f	0	0.00	en_attente	5	3	9	LocalitÃ© Mayo-DarlÃ©	eleveur_12-2025_001	2025-12-18
10	pÃªcheur_Prod_Dir	699010	pÃªcheur	f	0	0.00	en_attente	5	4	10	LocalitÃ© Dir	pecheur_12-2025_001	2025-12-18
11	Ã©leveur_Prod_Djohong	699011	Ã©leveur	f	0	0.00	en_attente	5	4	11	LocalitÃ© Djohong	eleveur_12-2025_001	2025-12-18
12	pÃªcheur_Prod_Meiganga	699012	pÃªcheur	f	0	0.00	en_attente	5	4	12	LocalitÃ© Meiganga	pecheur_12-2025_001	2025-12-18
13	artisan_Prod_Ngaoui	699013	artisan	f	0	0.00	en_attente	5	4	13	LocalitÃ© Ngaoui	artisan_12-2025_001	2025-12-18
14	artisan_Prod_Belel	699014	artisan	f	0	0.00	en_attente	5	5	14	LocalitÃ© Belel	artisan_12-2025_001	2025-12-18
15	alimentaire manufacture_Prod_Martap	699015	alimentaire manufacture	f	0	0.00	en_attente	5	5	15	LocalitÃ© Martap	alim_12-2025_001	2025-12-18
16	autre_Prod_Mbe	699016	autre	f	0	0.00	en_attente	5	5	16	LocalitÃ© Mbe	autre_12-2025_001	2025-12-18
17	agriculteur_Prod_Nganha	699017	agriculteur	f	0	0.00	en_attente	5	5	17	LocalitÃ© Nganha	agri_12-2025_001	2025-12-18
18	coopÃ©rative_Prod_NgaoundÃ©rÃ© I	699018	coopÃ©rative	f	0	0.00	en_attente	5	5	18	LocalitÃ© NgaoundÃ©rÃ© I	coop_12-2025_001	2025-12-18
19	artisan_Prod_NgaoundÃ©rÃ© II	699019	artisan	f	0	0.00	en_attente	5	5	19	LocalitÃ© NgaoundÃ©rÃ© II	artisan_12-2025_001	2025-12-18
20	Ã©leveur_Prod_NgaoundÃ©rÃ© III	699020	Ã©leveur	f	0	0.00	en_attente	5	5	20	LocalitÃ© NgaoundÃ©rÃ© III	eleveur_12-2025_001	2025-12-18
21	alimentaire manufacture_Prod_Nyambaka	699021	alimentaire manufacture	f	0	0.00	en_attente	5	5	21	LocalitÃ© Nyambaka	alim_12-2025_001	2025-12-18
22	pÃªcheur_Prod_Bibey	699022	pÃªcheur	f	0	0.00	en_attente	1	6	22	LocalitÃ© Bibey	pecheur_12-2025_001	2025-12-18
23	individuel_Prod_Lembe-Yezoum	699023	individuel	f	0	0.00	en_attente	1	6	23	LocalitÃ© Lembe-Yezoum	indiv_12-2025_001	2025-12-18
24	coopÃ©rative_Prod_Mbandjock	699024	coopÃ©rative	f	0	0.00	en_attente	1	6	24	LocalitÃ© Mbandjock	coop_12-2025_001	2025-12-18
25	autre_Prod_Minta	699025	autre	f	0	0.00	en_attente	1	6	25	LocalitÃ© Minta	autre_12-2025_001	2025-12-18
26	Ã©leveur_Prod_Nanga-Eboko	699026	Ã©leveur	f	0	0.00	en_attente	1	6	26	LocalitÃ© Nanga-Eboko	eleveur_12-2025_001	2025-12-18
27	coopÃ©rative_Prod_Nkoteng	699027	coopÃ©rative	f	0	0.00	en_attente	1	6	27	LocalitÃ© Nkoteng	coop_12-2025_001	2025-12-18
28	coopÃ©rative_Prod_Nsem	699028	coopÃ©rative	f	0	0.00	en_attente	1	6	28	LocalitÃ© Nsem	coop_12-2025_001	2025-12-18
29	agriculteur_Prod_Batchenga	699029	agriculteur	f	0	0.00	en_attente	1	7	29	LocalitÃ© Batchenga	agri_12-2025_001	2025-12-18
30	individuel_Prod_Ebebda	699030	individuel	f	0	0.00	en_attente	1	7	30	LocalitÃ© Ebebda	indiv_12-2025_001	2025-12-18
31	autre_Prod_Elig-Mfomo	699031	autre	f	0	0.00	en_attente	1	7	31	LocalitÃ© Elig-Mfomo	autre_12-2025_001	2025-12-18
32	pÃªcheur_Prod_Evodoula	699032	pÃªcheur	f	0	0.00	en_attente	1	7	32	LocalitÃ© Evodoula	pecheur_12-2025_001	2025-12-18
33	agriculteur_Prod_Lobo	699033	agriculteur	f	0	0.00	en_attente	1	7	33	LocalitÃ© Lobo	agri_12-2025_001	2025-12-18
34	individuel_Prod_MonatÃ©lÃ©	699034	individuel	f	0	0.00	en_attente	1	7	34	LocalitÃ© MonatÃ©lÃ©	indiv_12-2025_001	2025-12-18
35	artisan_Prod_Obala	699035	artisan	f	0	0.00	en_attente	1	7	35	LocalitÃ© Obala	artisan_12-2025_001	2025-12-18
36	artisan_Prod_Okola	699036	artisan	f	0	0.00	en_attente	1	7	36	LocalitÃ© Okola	artisan_12-2025_001	2025-12-18
37	pÃªcheur_Prod_Sa'a	699037	pÃªcheur	f	0	0.00	en_attente	1	7	37	LocalitÃ© Sa'a	pecheur_12-2025_001	2025-12-18
38	artisan_Prod_Bafia	699038	artisan	f	0	0.00	en_attente	1	8	38	LocalitÃ© Bafia	artisan_12-2025_001	2025-12-18
39	alimentaire manufacture_Prod_Bokito	699039	alimentaire manufacture	f	0	0.00	en_attente	1	8	39	LocalitÃ© Bokito	alim_12-2025_001	2025-12-18
40	agriculteur_Prod_Deuk	699040	agriculteur	f	0	0.00	en_attente	1	8	40	LocalitÃ© Deuk	agri_12-2025_001	2025-12-18
41	coopÃ©rative_Prod_Kiiki	699041	coopÃ©rative	f	0	0.00	en_attente	1	8	41	LocalitÃ© Kiiki	coop_12-2025_001	2025-12-18
42	agriculteur_Prod_Kon-Yambetta	699042	agriculteur	f	0	0.00	en_attente	1	8	42	LocalitÃ© Kon-Yambetta	agri_12-2025_001	2025-12-18
43	individuel_Prod_MakÃ©nÃ©nÃ©	699043	individuel	f	0	0.00	en_attente	1	8	43	LocalitÃ© MakÃ©nÃ©nÃ©	indiv_12-2025_001	2025-12-18
44	individuel_Prod_NdikinimÃ©ki	699044	individuel	f	0	0.00	en_attente	1	8	44	LocalitÃ© NdikinimÃ©ki	indiv_12-2025_001	2025-12-18
45	individuel_Prod_Nitoukou	699045	individuel	f	0	0.00	en_attente	1	8	45	LocalitÃ© Nitoukou	indiv_12-2025_001	2025-12-18
46	agriculteur_Prod_Ombessa	699046	agriculteur	f	0	0.00	en_attente	1	8	46	LocalitÃ© Ombessa	agri_12-2025_001	2025-12-18
47	coopÃ©rative_Prod_Mbangassina	699047	coopÃ©rative	f	0	0.00	en_attente	1	9	47	LocalitÃ© Mbangassina	coop_12-2025_001	2025-12-18
48	alimentaire manufacture_Prod_NgambÃ¨-Tikar	699048	alimentaire manufacture	f	0	0.00	en_attente	1	9	48	LocalitÃ© NgambÃ¨-Tikar	alim_12-2025_001	2025-12-18
49	Ã©leveur_Prod_Ngoro	699049	Ã©leveur	f	0	0.00	en_attente	1	9	49	LocalitÃ© Ngoro	eleveur_12-2025_001	2025-12-18
50	alimentaire manufacture_Prod_Ntui	699050	alimentaire manufacture	f	0	0.00	en_attente	1	9	50	LocalitÃ© Ntui	alim_12-2025_001	2025-12-18
102	individuel_Prod_Mboma	699098	individuel	f	0	0.00	en_attente	6	17	98	LocalitÃ© Mboma	indiv_12-2025_001	2025-12-18
51	alimentaire manufacture_Prod_Yoko	699051	alimentaire manufacture	f	0	0.00	en_attente	1	9	51	LocalitÃ© Yoko	alim_12-2025_001	2025-12-18
52	agriculteur_Prod_Afanloum	699052	agriculteur	f	0	0.00	en_attente	1	10	52	LocalitÃ© Afanloum	agri_12-2025_001	2025-12-18
53	autre_Prod_Assamba	699053	autre	f	0	0.00	en_attente	1	10	53	LocalitÃ© Assamba	autre_12-2025_001	2025-12-18
54	alimentaire manufacture_Prod_AwaÃ©	699054	alimentaire manufacture	f	0	0.00	en_attente	1	10	54	LocalitÃ© AwaÃ©	alim_12-2025_001	2025-12-18
55	pÃªcheur_Prod_Edzendouan	699055	pÃªcheur	f	0	0.00	en_attente	1	10	55	LocalitÃ© Edzendouan	pecheur_12-2025_001	2025-12-18
56	alimentaire manufacture_Prod_Esse	699056	alimentaire manufacture	f	0	0.00	en_attente	1	10	56	LocalitÃ© Esse	alim_12-2025_001	2025-12-18
57	Ã©leveur_Prod_Mfou	699057	Ã©leveur	f	0	0.00	en_attente	1	10	57	LocalitÃ© Mfou	eleveur_12-2025_001	2025-12-18
58	artisan_Prod_Nkolafamba	699058	artisan	f	0	0.00	en_attente	1	10	58	LocalitÃ© Nkolafamba	artisan_12-2025_001	2025-12-18
59	alimentaire manufacture_Prod_Soa	699059	alimentaire manufacture	f	0	0.00	en_attente	1	10	59	LocalitÃ© Soa	alim_12-2025_001	2025-12-18
60	pÃªcheur_Prod_Akono	699060	pÃªcheur	f	0	0.00	en_attente	1	11	60	LocalitÃ© Akono	pecheur_12-2025_001	2025-12-18
61	artisan_Prod_Bikok	699061	artisan	f	0	0.00	en_attente	1	11	61	LocalitÃ© Bikok	artisan_12-2025_001	2025-12-18
62	pÃªcheur_Prod_Mbankomo	699062	pÃªcheur	f	0	0.00	en_attente	1	11	62	LocalitÃ© Mbankomo	pecheur_12-2025_001	2025-12-18
63	individuel_Prod_Ngoumou	699063	individuel	f	0	0.00	en_attente	1	11	63	LocalitÃ© Ngoumou	indiv_12-2025_001	2025-12-18
64	agriculteur_Prod_YaoundÃ© I	699064	agriculteur	f	0	0.00	en_attente	1	12	64	LocalitÃ© YaoundÃ© I	agri_12-2025_001	2025-12-18
65	pÃªcheur_Prod_YaoundÃ© II	699065	pÃªcheur	f	0	0.00	en_attente	1	12	65	LocalitÃ© YaoundÃ© II	pecheur_12-2025_001	2025-12-18
66	agriculteur_Prod_YaoundÃ© III	699066	agriculteur	f	0	0.00	en_attente	1	12	66	LocalitÃ© YaoundÃ© III	agri_12-2025_001	2025-12-18
67	agriculteur_Prod_YaoundÃ© IV	699067	agriculteur	f	0	0.00	en_attente	1	12	67	LocalitÃ© YaoundÃ© IV	agri_12-2025_001	2025-12-18
68	Ã©leveur_Prod_YaoundÃ© V	699068	Ã©leveur	f	0	0.00	en_attente	1	12	68	LocalitÃ© YaoundÃ© V	eleveur_12-2025_001	2025-12-18
69	artisan_Prod_YaoundÃ© VI	699069	artisan	f	0	0.00	en_attente	1	12	69	LocalitÃ© YaoundÃ© VI	artisan_12-2025_001	2025-12-18
70	agriculteur_Prod_YaoundÃ© VII	699070	agriculteur	f	0	0.00	en_attente	1	12	70	LocalitÃ© YaoundÃ© VII	agri_12-2025_001	2025-12-18
71	individuel_Prod_Ã‰sÃ©ka	699075	individuel	f	0	0.00	en_attente	1	13	75	LocalitÃ© Ã‰sÃ©ka	indiv_12-2025_001	2025-12-18
72	autre_Prod_Biyouha	699071	autre	f	0	0.00	en_attente	1	13	71	LocalitÃ© Biyouha	autre_12-2025_001	2025-12-18
73	pÃªcheur_Prod_Bondjock	699072	pÃªcheur	f	0	0.00	en_attente	1	13	72	LocalitÃ© Bondjock	pecheur_12-2025_001	2025-12-18
74	coopÃ©rative_Prod_Bot-Makak	699073	coopÃ©rative	f	0	0.00	en_attente	1	13	73	LocalitÃ© Bot-Makak	coop_12-2025_001	2025-12-18
75	coopÃ©rative_Prod_Dibang	699074	coopÃ©rative	f	0	0.00	en_attente	1	13	74	LocalitÃ© Dibang	coop_12-2025_001	2025-12-18
76	pÃªcheur_Prod_Makak	699076	pÃªcheur	f	0	0.00	en_attente	1	13	76	LocalitÃ© Makak	pecheur_12-2025_001	2025-12-18
77	pÃªcheur_Prod_Matomb	699077	pÃªcheur	f	0	0.00	en_attente	1	13	77	LocalitÃ© Matomb	pecheur_12-2025_001	2025-12-18
78	Ã©leveur_Prod_Messondo	699078	Ã©leveur	f	0	0.00	en_attente	1	13	78	LocalitÃ© Messondo	eleveur_12-2025_001	2025-12-18
79	pÃªcheur_Prod_Ngog-Mapubi	699079	pÃªcheur	f	0	0.00	en_attente	1	13	79	LocalitÃ© Ngog-Mapubi	pecheur_12-2025_001	2025-12-18
80	autre_Prod_Nguibassal	699080	autre	f	0	0.00	en_attente	1	13	80	LocalitÃ© Nguibassal	autre_12-2025_001	2025-12-18
81	agriculteur_Prod_Akonolinga	699081	agriculteur	f	0	0.00	en_attente	1	14	81	LocalitÃ© Akonolinga	agri_12-2025_001	2025-12-18
82	alimentaire manufacture_Prod_Ayos	699082	alimentaire manufacture	f	0	0.00	en_attente	1	14	82	LocalitÃ© Ayos	alim_12-2025_001	2025-12-18
83	agriculteur_Prod_Endom	699083	agriculteur	f	0	0.00	en_attente	1	14	83	LocalitÃ© Endom	agri_12-2025_001	2025-12-18
84	Ã©leveur_Prod_Mengang	699084	Ã©leveur	f	0	0.00	en_attente	1	14	84	LocalitÃ© Mengang	eleveur_12-2025_001	2025-12-18
85	agriculteur_Prod_Nyakokombo	699085	agriculteur	f	0	0.00	en_attente	1	14	85	LocalitÃ© Nyakokombo	agri_12-2025_001	2025-12-18
86	coopÃ©rative_Prod_Mbalmayo	699355	coopÃ©rative	f	0	0.00	en_attente	1	15	355	LocalitÃ© Mbalmayo	coop_12-2025_001	2025-12-18
87	pÃªcheur_Prod_Mengueme	699356	pÃªcheur	f	0	0.00	en_attente	1	15	356	LocalitÃ© Mengueme	pecheur_12-2025_001	2025-12-18
88	Ã©leveur_Prod_Ngomedzap	699357	Ã©leveur	f	0	0.00	en_attente	1	15	357	LocalitÃ© Ngomedzap	eleveur_12-2025_001	2025-12-18
89	individuel_Prod_Nkolmetet	699358	individuel	f	0	0.00	en_attente	1	15	358	LocalitÃ© Nkolmetet	indiv_12-2025_001	2025-12-18
90	pÃªcheur_Prod_Gari-Gombo	699086	pÃªcheur	f	0	0.00	en_attente	6	16	86	LocalitÃ© Gari-Gombo	pecheur_12-2025_001	2025-12-18
91	Ã©leveur_Prod_Moloundou	699087	Ã©leveur	f	0	0.00	en_attente	6	16	87	LocalitÃ© Moloundou	eleveur_12-2025_001	2025-12-18
92	pÃªcheur_Prod_SalapoumbÃ©	699088	pÃªcheur	f	0	0.00	en_attente	6	16	88	LocalitÃ© SalapoumbÃ©	pecheur_12-2025_001	2025-12-18
93	agriculteur_Prod_Yokadouma	699089	agriculteur	f	0	0.00	en_attente	6	16	89	LocalitÃ© Yokadouma	agri_12-2025_001	2025-12-18
94	Ã©leveur_Prod_Abong-Mbang	699090	Ã©leveur	f	0	0.00	en_attente	6	17	90	LocalitÃ© Abong-Mbang	eleveur_12-2025_001	2025-12-18
95	agriculteur_Prod_Bebend	699091	agriculteur	f	0	0.00	en_attente	6	17	91	LocalitÃ© Bebend	agri_12-2025_001	2025-12-18
96	autre_Prod_Dimako	699092	autre	f	0	0.00	en_attente	6	17	92	LocalitÃ© Dimako	autre_12-2025_001	2025-12-18
97	pÃªcheur_Prod_Dja	699093	pÃªcheur	f	0	0.00	en_attente	6	17	93	LocalitÃ© Dja	pecheur_12-2025_001	2025-12-18
98	coopÃ©rative_Prod_DoumÃ©	699095	coopÃ©rative	f	0	0.00	en_attente	6	17	95	LocalitÃ© DoumÃ©	coop_12-2025_001	2025-12-18
99	artisan_Prod_Doumaintang	699094	artisan	f	0	0.00	en_attente	6	17	94	LocalitÃ© Doumaintang	artisan_12-2025_001	2025-12-18
100	individuel_Prod_LomiÃ©	699096	individuel	f	0	0.00	en_attente	6	17	96	LocalitÃ© LomiÃ©	indiv_12-2025_001	2025-12-18
101	autre_Prod_Mboanz	699097	autre	f	0	0.00	en_attente	6	17	97	LocalitÃ© Mboanz	autre_12-2025_001	2025-12-18
103	individuel_Prod_Messamena	699099	individuel	f	0	0.00	en_attente	6	17	99	LocalitÃ© Messamena	indiv_12-2025_001	2025-12-18
104	Ã©leveur_Prod_Messok	699100	Ã©leveur	f	0	0.00	en_attente	6	17	100	LocalitÃ© Messok	eleveur_12-2025_001	2025-12-18
105	autre_Prod_Ngoyla	699101	autre	f	0	0.00	en_attente	6	17	101	LocalitÃ© Ngoyla	autre_12-2025_001	2025-12-18
106	individuel_Prod_Nguelemendouka	699102	individuel	f	0	0.00	en_attente	6	17	102	LocalitÃ© Nguelemendouka	indiv_12-2025_001	2025-12-18
107	individuel_Prod_Somalomo	699103	individuel	f	0	0.00	en_attente	6	17	103	LocalitÃ© Somalomo	indiv_12-2025_001	2025-12-18
108	pÃªcheur_Prod_Batouri	699104	pÃªcheur	f	0	0.00	en_attente	6	18	104	LocalitÃ© Batouri	pecheur_12-2025_001	2025-12-18
109	Ã©leveur_Prod_BombÃ©	699105	Ã©leveur	f	0	0.00	en_attente	6	18	105	LocalitÃ© BombÃ©	eleveur_12-2025_001	2025-12-18
110	agriculteur_Prod_Kette	699106	agriculteur	f	0	0.00	en_attente	6	18	106	LocalitÃ© Kette	agri_12-2025_001	2025-12-18
111	artisan_Prod_Mbang	699107	artisan	f	0	0.00	en_attente	6	18	107	LocalitÃ© Mbang	artisan_12-2025_001	2025-12-18
112	Ã©leveur_Prod_Mbotoro	699108	Ã©leveur	f	0	0.00	en_attente	6	18	108	LocalitÃ© Mbotoro	eleveur_12-2025_001	2025-12-18
113	Ã©leveur_Prod_Ndelele	699109	Ã©leveur	f	0	0.00	en_attente	6	18	109	LocalitÃ© Ndelele	eleveur_12-2025_001	2025-12-18
114	agriculteur_Prod_Ndem-Nam	699110	agriculteur	f	0	0.00	en_attente	6	18	110	LocalitÃ© Ndem-Nam	agri_12-2025_001	2025-12-18
115	coopÃ©rative_Prod_BÃ©labo	699111	coopÃ©rative	f	0	0.00	en_attente	6	19	111	LocalitÃ© BÃ©labo	coop_12-2025_001	2025-12-18
116	agriculteur_Prod_BÃ©tarÃ©-Oya	699114	agriculteur	f	0	0.00	en_attente	6	19	114	LocalitÃ© BÃ©tarÃ©-Oya	agri_12-2025_001	2025-12-18
117	coopÃ©rative_Prod_Bertoua I	699112	coopÃ©rative	f	0	0.00	en_attente	6	19	112	LocalitÃ© Bertoua I	coop_12-2025_001	2025-12-18
118	agriculteur_Prod_Bertoua II	699113	agriculteur	f	0	0.00	en_attente	6	19	113	LocalitÃ© Bertoua II	agri_12-2025_001	2025-12-18
119	individuel_Prod_Diang	699115	individuel	f	0	0.00	en_attente	6	19	115	LocalitÃ© Diang	indiv_12-2025_001	2025-12-18
120	Ã©leveur_Prod_Garoua-BoulaÃ¯	699116	Ã©leveur	f	0	0.00	en_attente	6	19	116	LocalitÃ© Garoua-BoulaÃ¯	eleveur_12-2025_001	2025-12-18
121	autre_Prod_Mandjou	699117	autre	f	0	0.00	en_attente	6	19	117	LocalitÃ© Mandjou	autre_12-2025_001	2025-12-18
122	coopÃ©rative_Prod_Ngoura	699118	coopÃ©rative	f	0	0.00	en_attente	6	19	118	LocalitÃ© Ngoura	coop_12-2025_001	2025-12-18
123	autre_Prod_Bogo	699119	autre	f	0	0.00	en_attente	4	20	119	LocalitÃ© Bogo	autre_12-2025_001	2025-12-18
124	pÃªcheur_Prod_Dargala	699120	pÃªcheur	f	0	0.00	en_attente	4	20	120	LocalitÃ© Dargala	pecheur_12-2025_001	2025-12-18
125	alimentaire manufacture_Prod_Gazawa	699121	alimentaire manufacture	f	0	0.00	en_attente	4	20	121	LocalitÃ© Gazawa	alim_12-2025_001	2025-12-18
126	agriculteur_Prod_Maroua I	699122	agriculteur	f	0	0.00	en_attente	4	20	122	LocalitÃ© Maroua I	agri_12-2025_001	2025-12-18
127	individuel_Prod_Maroua II	699123	individuel	f	0	0.00	en_attente	4	20	123	LocalitÃ© Maroua II	indiv_12-2025_001	2025-12-18
128	coopÃ©rative_Prod_Maroua III	699124	coopÃ©rative	f	0	0.00	en_attente	4	20	124	LocalitÃ© Maroua III	coop_12-2025_001	2025-12-18
129	autre_Prod_Meri	699125	autre	f	0	0.00	en_attente	4	20	125	LocalitÃ© Meri	autre_12-2025_001	2025-12-18
130	autre_Prod_Ndoukoula	699126	autre	f	0	0.00	en_attente	4	20	126	LocalitÃ© Ndoukoula	autre_12-2025_001	2025-12-18
131	autre_Prod_PettÃ©	699127	autre	f	0	0.00	en_attente	4	20	127	LocalitÃ© PettÃ©	autre_12-2025_001	2025-12-18
132	Ã©leveur_Prod_Blangoua	699128	Ã©leveur	f	0	0.00	en_attente	4	21	128	LocalitÃ© Blangoua	eleveur_12-2025_001	2025-12-18
133	artisan_Prod_Darak	699129	artisan	f	0	0.00	en_attente	4	21	129	LocalitÃ© Darak	artisan_12-2025_001	2025-12-18
134	pÃªcheur_Prod_Fotokol	699130	pÃªcheur	f	0	0.00	en_attente	4	21	130	LocalitÃ© Fotokol	pecheur_12-2025_001	2025-12-18
135	artisan_Prod_Goulfey	699131	artisan	f	0	0.00	en_attente	4	21	131	LocalitÃ© Goulfey	artisan_12-2025_001	2025-12-18
136	Ã©leveur_Prod_Hile-Alifa	699132	Ã©leveur	f	0	0.00	en_attente	4	21	132	LocalitÃ© Hile-Alifa	eleveur_12-2025_001	2025-12-18
137	pÃªcheur_Prod_KoussÃ©ri	699133	pÃªcheur	f	0	0.00	en_attente	4	21	133	LocalitÃ© KoussÃ©ri	pecheur_12-2025_001	2025-12-18
138	alimentaire manufacture_Prod_Logone-Birni	699134	alimentaire manufacture	f	0	0.00	en_attente	4	21	134	LocalitÃ© Logone-Birni	alim_12-2025_001	2025-12-18
139	Ã©leveur_Prod_Makary	699135	Ã©leveur	f	0	0.00	en_attente	4	21	135	LocalitÃ© Makary	eleveur_12-2025_001	2025-12-18
140	coopÃ©rative_Prod_Waza	699136	coopÃ©rative	f	0	0.00	en_attente	4	21	136	LocalitÃ© Waza	coop_12-2025_001	2025-12-18
141	alimentaire manufacture_Prod_Zina	699137	alimentaire manufacture	f	0	0.00	en_attente	4	21	137	LocalitÃ© Zina	alim_12-2025_001	2025-12-18
142	artisan_Prod_Datcheka	699138	artisan	f	0	0.00	en_attente	4	22	138	LocalitÃ© Datcheka	artisan_12-2025_001	2025-12-18
143	alimentaire manufacture_Prod_Gobo	699139	alimentaire manufacture	f	0	0.00	en_attente	4	22	139	LocalitÃ© Gobo	alim_12-2025_001	2025-12-18
144	artisan_Prod_GuÃ©rÃ©	699140	artisan	f	0	0.00	en_attente	4	22	140	LocalitÃ© GuÃ©rÃ©	artisan_12-2025_001	2025-12-18
145	individuel_Prod_KaÃ¯-KaÃ¯	699141	individuel	f	0	0.00	en_attente	4	22	141	LocalitÃ© KaÃ¯-KaÃ¯	indiv_12-2025_001	2025-12-18
146	individuel_Prod_Kalfou	699142	individuel	f	0	0.00	en_attente	4	22	142	LocalitÃ© Kalfou	indiv_12-2025_001	2025-12-18
147	individuel_Prod_Kar-Hay	699143	individuel	f	0	0.00	en_attente	4	22	143	LocalitÃ© Kar-Hay	indiv_12-2025_001	2025-12-18
148	coopÃ©rative_Prod_Maga	699144	coopÃ©rative	f	0	0.00	en_attente	4	22	144	LocalitÃ© Maga	coop_12-2025_001	2025-12-18
149	Ã©leveur_Prod_Tchati-Bali	699145	Ã©leveur	f	0	0.00	en_attente	4	22	145	LocalitÃ© Tchati-Bali	eleveur_12-2025_001	2025-12-18
150	autre_Prod_Vele	699146	autre	f	0	0.00	en_attente	4	22	146	LocalitÃ© Vele	autre_12-2025_001	2025-12-18
151	coopÃ©rative_Prod_Wina	699147	coopÃ©rative	f	0	0.00	en_attente	4	22	147	LocalitÃ© Wina	coop_12-2025_001	2025-12-18
152	autre_Prod_Yagoua	699148	autre	f	0	0.00	en_attente	4	22	148	LocalitÃ© Yagoua	autre_12-2025_001	2025-12-18
153	coopÃ©rative_Prod_Guidiguis	699149	coopÃ©rative	f	0	0.00	en_attente	4	23	149	LocalitÃ© Guidiguis	coop_12-2025_001	2025-12-18
154	artisan_Prod_KaÃ©lÃ©	699150	artisan	f	0	0.00	en_attente	4	23	150	LocalitÃ© KaÃ©lÃ©	artisan_12-2025_001	2025-12-18
155	pÃªcheur_Prod_Mindif	699151	pÃªcheur	f	0	0.00	en_attente	4	23	151	LocalitÃ© Mindif	pecheur_12-2025_001	2025-12-18
156	autre_Prod_Moulvoudaye	699152	autre	f	0	0.00	en_attente	4	23	152	LocalitÃ© Moulvoudaye	autre_12-2025_001	2025-12-18
157	Ã©leveur_Prod_Moutourwa	699153	Ã©leveur	f	0	0.00	en_attente	4	23	153	LocalitÃ© Moutourwa	eleveur_12-2025_001	2025-12-18
158	autre_Prod_Porhi	699154	autre	f	0	0.00	en_attente	4	23	154	LocalitÃ© Porhi	autre_12-2025_001	2025-12-18
159	individuel_Prod_Taibong	699155	individuel	f	0	0.00	en_attente	4	23	155	LocalitÃ© Taibong	indiv_12-2025_001	2025-12-18
160	agriculteur_Prod_Kolofata	699156	agriculteur	f	0	0.00	en_attente	4	24	156	LocalitÃ© Kolofata	agri_12-2025_001	2025-12-18
161	autre_Prod_Mora	699157	autre	f	0	0.00	en_attente	4	24	157	LocalitÃ© Mora	autre_12-2025_001	2025-12-18
162	artisan_Prod_TokombÃ©rÃ©	699158	artisan	f	0	0.00	en_attente	4	24	158	LocalitÃ© TokombÃ©rÃ©	artisan_12-2025_001	2025-12-18
163	agriculteur_Prod_Bourrha	699159	agriculteur	f	0	0.00	en_attente	4	25	159	LocalitÃ© Bourrha	agri_12-2025_001	2025-12-18
164	autre_Prod_Hina	699160	autre	f	0	0.00	en_attente	4	25	160	LocalitÃ© Hina	autre_12-2025_001	2025-12-18
165	autre_Prod_Koza	699161	autre	f	0	0.00	en_attente	4	25	161	LocalitÃ© Koza	autre_12-2025_001	2025-12-18
166	Ã©leveur_Prod_Mayo-Moskota	699162	Ã©leveur	f	0	0.00	en_attente	4	25	162	LocalitÃ© Mayo-Moskota	eleveur_12-2025_001	2025-12-18
167	agriculteur_Prod_Mogode	699163	agriculteur	f	0	0.00	en_attente	4	25	163	LocalitÃ© Mogode	agri_12-2025_001	2025-12-18
168	agriculteur_Prod_Mokolo	699164	agriculteur	f	0	0.00	en_attente	4	25	164	LocalitÃ© Mokolo	agri_12-2025_001	2025-12-18
169	artisan_Prod_SoulÃ©dÃ©-Roua	699165	artisan	f	0	0.00	en_attente	4	25	165	LocalitÃ© SoulÃ©dÃ©-Roua	artisan_12-2025_001	2025-12-18
170	pÃªcheur_Prod_Abo Fiko (BonalÃ©a)	699187	pÃªcheur	f	0	0.00	en_attente	2	26	187	LocalitÃ© Abo Fiko (BonalÃ©a)	pecheur_12-2025_001	2025-12-18
171	Ã©leveur_Prod_BarÃ©-Bakem	699188	Ã©leveur	f	0	0.00	en_attente	2	26	188	LocalitÃ© BarÃ©-Bakem	eleveur_12-2025_001	2025-12-18
172	autre_Prod_Dibombari	699189	autre	f	0	0.00	en_attente	2	26	189	LocalitÃ© Dibombari	autre_12-2025_001	2025-12-18
173	coopÃ©rative_Prod_Loum	699190	coopÃ©rative	f	0	0.00	en_attente	2	26	190	LocalitÃ© Loum	coop_12-2025_001	2025-12-18
174	artisan_Prod_Manjo	699191	artisan	f	0	0.00	en_attente	2	26	191	LocalitÃ© Manjo	artisan_12-2025_001	2025-12-18
175	pÃªcheur_Prod_Mbanga	699192	pÃªcheur	f	0	0.00	en_attente	2	26	192	LocalitÃ© Mbanga	pecheur_12-2025_001	2025-12-18
176	coopÃ©rative_Prod_Melong	699193	coopÃ©rative	f	0	0.00	en_attente	2	26	193	LocalitÃ© Melong	coop_12-2025_001	2025-12-18
177	individuel_Prod_Mombo	699194	individuel	f	0	0.00	en_attente	2	26	194	LocalitÃ© Mombo	indiv_12-2025_001	2025-12-18
178	pÃªcheur_Prod_Njombe-Penja	699195	pÃªcheur	f	0	0.00	en_attente	2	26	195	LocalitÃ© Njombe-Penja	pecheur_12-2025_001	2025-12-18
179	Ã©leveur_Prod_Nkongsamba I	699196	Ã©leveur	f	0	0.00	en_attente	2	26	196	LocalitÃ© Nkongsamba I	eleveur_12-2025_001	2025-12-18
180	artisan_Prod_Nkongsamba II	699197	artisan	f	0	0.00	en_attente	2	26	197	LocalitÃ© Nkongsamba II	artisan_12-2025_001	2025-12-18
181	pÃªcheur_Prod_Nkongsamba III	699198	pÃªcheur	f	0	0.00	en_attente	2	26	198	LocalitÃ© Nkongsamba III	pecheur_12-2025_001	2025-12-18
182	autre_Prod_Nlonako	699199	autre	f	0	0.00	en_attente	2	26	199	LocalitÃ© Nlonako	autre_12-2025_001	2025-12-18
183	agriculteur_Prod_Nkondjock	699183	agriculteur	f	0	0.00	en_attente	2	27	183	LocalitÃ© Nkondjock	agri_12-2025_001	2025-12-18
184	individuel_Prod_Nord-MakombÃ©	699184	individuel	f	0	0.00	en_attente	2	27	184	LocalitÃ© Nord-MakombÃ©	indiv_12-2025_001	2025-12-18
185	artisan_Prod_Yabassi	699185	artisan	f	0	0.00	en_attente	2	27	185	LocalitÃ© Yabassi	artisan_12-2025_001	2025-12-18
186	individuel_Prod_Yingui	699186	individuel	f	0	0.00	en_attente	2	27	186	LocalitÃ© Yingui	indiv_12-2025_001	2025-12-18
187	autre_Prod_Ã‰dÃ©a I	699174	autre	f	0	0.00	en_attente	2	28	174	LocalitÃ© Ã‰dÃ©a I	autre_12-2025_001	2025-12-18
188	Ã©leveur_Prod_Ã‰dÃ©a II	699175	Ã©leveur	f	0	0.00	en_attente	2	28	175	LocalitÃ© Ã‰dÃ©a II	eleveur_12-2025_001	2025-12-18
189	pÃªcheur_Prod_Dibamba	699172	pÃªcheur	f	0	0.00	en_attente	2	28	172	LocalitÃ© Dibamba	pecheur_12-2025_001	2025-12-18
190	Ã©leveur_Prod_DizanguÃ©	699173	Ã©leveur	f	0	0.00	en_attente	2	28	173	LocalitÃ© DizanguÃ©	eleveur_12-2025_001	2025-12-18
191	Ã©leveur_Prod_Massock-Songloulou	699176	Ã©leveur	f	0	0.00	en_attente	2	28	176	LocalitÃ© Massock-Songloulou	eleveur_12-2025_001	2025-12-18
192	individuel_Prod_Mouanko	699177	individuel	f	0	0.00	en_attente	2	28	177	LocalitÃ© Mouanko	indiv_12-2025_001	2025-12-18
193	artisan_Prod_Ndom	699178	artisan	f	0	0.00	en_attente	2	28	178	LocalitÃ© Ndom	artisan_12-2025_001	2025-12-18
194	artisan_Prod_Ngambe	699179	artisan	f	0	0.00	en_attente	2	28	179	LocalitÃ© Ngambe	artisan_12-2025_001	2025-12-18
195	pÃªcheur_Prod_Ngwei	699180	pÃªcheur	f	0	0.00	en_attente	2	28	180	LocalitÃ© Ngwei	pecheur_12-2025_001	2025-12-18
196	Ã©leveur_Prod_Nyanon	699181	Ã©leveur	f	0	0.00	en_attente	2	28	181	LocalitÃ© Nyanon	eleveur_12-2025_001	2025-12-18
197	artisan_Prod_Pouma	699182	artisan	f	0	0.00	en_attente	2	28	182	LocalitÃ© Pouma	artisan_12-2025_001	2025-12-18
198	pÃªcheur_Prod_Douala I	699166	pÃªcheur	f	0	0.00	en_attente	2	29	166	LocalitÃ© Douala I	pecheur_12-2025_001	2025-12-18
199	individuel_Prod_Douala II	699167	individuel	f	0	0.00	en_attente	2	29	167	LocalitÃ© Douala II	indiv_12-2025_001	2025-12-18
200	artisan_Prod_Douala III	699168	artisan	f	0	0.00	en_attente	2	29	168	LocalitÃ© Douala III	artisan_12-2025_001	2025-12-18
201	coopÃ©rative_Prod_Douala IV	699169	coopÃ©rative	f	0	0.00	en_attente	2	29	169	LocalitÃ© Douala IV	coop_12-2025_001	2025-12-18
202	artisan_Prod_Douala V	699170	artisan	f	0	0.00	en_attente	2	29	170	LocalitÃ© Douala V	artisan_12-2025_001	2025-12-18
203	coopÃ©rative_Prod_Douala VI	699171	coopÃ©rative	f	0	0.00	en_attente	2	29	171	LocalitÃ© Douala VI	coop_12-2025_001	2025-12-18
204	autre_Prod_BaschÃ©o	699200	autre	f	0	0.00	en_attente	3	30	200	LocalitÃ© BaschÃ©o	autre_12-2025_001	2025-12-18
205	autre_Prod_Bibemi	699201	autre	f	0	0.00	en_attente	3	30	201	LocalitÃ© Bibemi	autre_12-2025_001	2025-12-18
206	alimentaire manufacture_Prod_Dembo	699202	alimentaire manufacture	f	0	0.00	en_attente	3	30	202	LocalitÃ© Dembo	alim_12-2025_001	2025-12-18
207	Ã©leveur_Prod_Demsa	699203	Ã©leveur	f	0	0.00	en_attente	3	30	203	LocalitÃ© Demsa	eleveur_12-2025_001	2025-12-18
208	pÃªcheur_Prod_Garoua I	699204	pÃªcheur	f	0	0.00	en_attente	3	30	204	LocalitÃ© Garoua I	pecheur_12-2025_001	2025-12-18
209	Ã©leveur_Prod_Garoua II	699205	Ã©leveur	f	0	0.00	en_attente	3	30	205	LocalitÃ© Garoua II	eleveur_12-2025_001	2025-12-18
210	alimentaire manufacture_Prod_Garoua III	699206	alimentaire manufacture	f	0	0.00	en_attente	3	30	206	LocalitÃ© Garoua III	alim_12-2025_001	2025-12-18
211	artisan_Prod_Lagdo	699207	artisan	f	0	0.00	en_attente	3	30	207	LocalitÃ© Lagdo	artisan_12-2025_001	2025-12-18
212	alimentaire manufacture_Prod_Mayo-Hourna	699208	alimentaire manufacture	f	0	0.00	en_attente	3	30	208	LocalitÃ© Mayo-Hourna	alim_12-2025_001	2025-12-18
213	alimentaire manufacture_Prod_Pitoa	699209	alimentaire manufacture	f	0	0.00	en_attente	3	30	209	LocalitÃ© Pitoa	alim_12-2025_001	2025-12-18
214	autre_Prod_Tcheboa	699210	autre	f	0	0.00	en_attente	3	30	210	LocalitÃ© Tcheboa	autre_12-2025_001	2025-12-18
215	pÃªcheur_Prod_Touroua	699211	pÃªcheur	f	0	0.00	en_attente	3	30	211	LocalitÃ© Touroua	pecheur_12-2025_001	2025-12-18
216	Ã©leveur_Prod_Beka	699212	Ã©leveur	f	0	0.00	en_attente	3	31	212	LocalitÃ© Beka	eleveur_12-2025_001	2025-12-18
217	artisan_Prod_Poli	699213	artisan	f	0	0.00	en_attente	3	31	213	LocalitÃ© Poli	artisan_12-2025_001	2025-12-18
218	Ã©leveur_Prod_Figuil	699214	Ã©leveur	f	0	0.00	en_attente	3	32	214	LocalitÃ© Figuil	eleveur_12-2025_001	2025-12-18
219	Ã©leveur_Prod_Guider	699215	Ã©leveur	f	0	0.00	en_attente	3	32	215	LocalitÃ© Guider	eleveur_12-2025_001	2025-12-18
220	agriculteur_Prod_Mayo-Oulo	699216	agriculteur	f	0	0.00	en_attente	3	32	216	LocalitÃ© Mayo-Oulo	agri_12-2025_001	2025-12-18
221	coopÃ©rative_Prod_Madingring	699217	coopÃ©rative	f	0	0.00	en_attente	3	33	217	LocalitÃ© Madingring	coop_12-2025_001	2025-12-18
222	individuel_Prod_Rey-Bouba	699218	individuel	f	0	0.00	en_attente	3	33	218	LocalitÃ© Rey-Bouba	indiv_12-2025_001	2025-12-18
223	Ã©leveur_Prod_TchollirÃ©	699219	Ã©leveur	f	0	0.00	en_attente	3	33	219	LocalitÃ© TchollirÃ©	eleveur_12-2025_001	2025-12-18
224	coopÃ©rative_Prod_Touboro	699220	coopÃ©rative	f	0	0.00	en_attente	3	33	220	LocalitÃ© Touboro	coop_12-2025_001	2025-12-18
225	pÃªcheur_Prod_Belo	699221	pÃªcheur	f	0	0.00	en_attente	9	34	221	LocalitÃ© Belo	pecheur_12-2025_001	2025-12-18
226	pÃªcheur_Prod_Bum	699222	pÃªcheur	f	0	0.00	en_attente	9	34	222	LocalitÃ© Bum	pecheur_12-2025_001	2025-12-18
227	artisan_Prod_Fundong	699223	artisan	f	0	0.00	en_attente	9	34	223	LocalitÃ© Fundong	artisan_12-2025_001	2025-12-18
228	alimentaire manufacture_Prod_Njinikom	699224	alimentaire manufacture	f	0	0.00	en_attente	9	34	224	LocalitÃ© Njinikom	alim_12-2025_001	2025-12-18
229	agriculteur_Prod_Jakiri	699225	agriculteur	f	0	0.00	en_attente	9	35	225	LocalitÃ© Jakiri	agri_12-2025_001	2025-12-18
230	pÃªcheur_Prod_Kumbo	699226	pÃªcheur	f	0	0.00	en_attente	9	35	226	LocalitÃ© Kumbo	pecheur_12-2025_001	2025-12-18
231	artisan_Prod_Mbven	699227	artisan	f	0	0.00	en_attente	9	35	227	LocalitÃ© Mbven	artisan_12-2025_001	2025-12-18
232	coopÃ©rative_Prod_Nkum	699228	coopÃ©rative	f	0	0.00	en_attente	9	35	228	LocalitÃ© Nkum	coop_12-2025_001	2025-12-18
233	pÃªcheur_Prod_Noni	699229	pÃªcheur	f	0	0.00	en_attente	9	35	229	LocalitÃ© Noni	pecheur_12-2025_001	2025-12-18
234	pÃªcheur_Prod_Oku	699230	pÃªcheur	f	0	0.00	en_attente	9	35	230	LocalitÃ© Oku	pecheur_12-2025_001	2025-12-18
235	agriculteur_Prod_Ako	699231	agriculteur	f	0	0.00	en_attente	9	36	231	LocalitÃ© Ako	agri_12-2025_001	2025-12-18
236	Ã©leveur_Prod_Misaje	699232	Ã©leveur	f	0	0.00	en_attente	9	36	232	LocalitÃ© Misaje	eleveur_12-2025_001	2025-12-18
237	artisan_Prod_Ndu	699233	artisan	f	0	0.00	en_attente	9	36	233	LocalitÃ© Ndu	artisan_12-2025_001	2025-12-18
238	coopÃ©rative_Prod_NkambÃ©	699234	coopÃ©rative	f	0	0.00	en_attente	9	36	234	LocalitÃ© NkambÃ©	coop_12-2025_001	2025-12-18
239	individuel_Prod_Nwa	699235	individuel	f	0	0.00	en_attente	9	36	235	LocalitÃ© Nwa	indiv_12-2025_001	2025-12-18
240	autre_Prod_Fungom	699236	autre	f	0	0.00	en_attente	9	37	236	LocalitÃ© Fungom	autre_12-2025_001	2025-12-18
241	coopÃ©rative_Prod_Furu-Awa	699237	coopÃ©rative	f	0	0.00	en_attente	9	37	237	LocalitÃ© Furu-Awa	coop_12-2025_001	2025-12-18
242	agriculteur_Prod_Menchum Valley	699238	agriculteur	f	0	0.00	en_attente	9	37	238	LocalitÃ© Menchum Valley	agri_12-2025_001	2025-12-18
243	alimentaire manufacture_Prod_Wum	699239	alimentaire manufacture	f	0	0.00	en_attente	9	37	239	LocalitÃ© Wum	alim_12-2025_001	2025-12-18
244	agriculteur_Prod_Bafut	699240	agriculteur	f	0	0.00	en_attente	9	38	240	LocalitÃ© Bafut	agri_12-2025_001	2025-12-18
245	Ã©leveur_Prod_Bali	699241	Ã©leveur	f	0	0.00	en_attente	9	38	241	LocalitÃ© Bali	eleveur_12-2025_001	2025-12-18
246	agriculteur_Prod_Bamenda I	699242	agriculteur	f	0	0.00	en_attente	9	38	242	LocalitÃ© Bamenda I	agri_12-2025_001	2025-12-18
247	pÃªcheur_Prod_Bamenda II	699243	pÃªcheur	f	0	0.00	en_attente	9	38	243	LocalitÃ© Bamenda II	pecheur_12-2025_001	2025-12-18
248	agriculteur_Prod_Bamenda III	699244	agriculteur	f	0	0.00	en_attente	9	38	244	LocalitÃ© Bamenda III	agri_12-2025_001	2025-12-18
249	alimentaire manufacture_Prod_Santa	699245	alimentaire manufacture	f	0	0.00	en_attente	9	38	245	LocalitÃ© Santa	alim_12-2025_001	2025-12-18
250	individuel_Prod_Tubah	699246	individuel	f	0	0.00	en_attente	9	38	246	LocalitÃ© Tubah	indiv_12-2025_001	2025-12-18
251	pÃªcheur_Prod_Batibo	699247	pÃªcheur	f	0	0.00	en_attente	9	39	247	LocalitÃ© Batibo	pecheur_12-2025_001	2025-12-18
252	Ã©leveur_Prod_Mbengwi	699248	Ã©leveur	f	0	0.00	en_attente	9	39	248	LocalitÃ© Mbengwi	eleveur_12-2025_001	2025-12-18
253	Ã©leveur_Prod_Ngie	699249	Ã©leveur	f	0	0.00	en_attente	9	39	249	LocalitÃ© Ngie	eleveur_12-2025_001	2025-12-18
254	agriculteur_Prod_Njikwa	699250	agriculteur	f	0	0.00	en_attente	9	39	250	LocalitÃ© Njikwa	agri_12-2025_001	2025-12-18
255	individuel_Prod_Widikum-Menka	699251	individuel	f	0	0.00	en_attente	9	39	251	LocalitÃ© Widikum-Menka	indiv_12-2025_001	2025-12-18
256	pÃªcheur_Prod_Babessi	699252	pÃªcheur	f	0	0.00	en_attente	9	40	252	LocalitÃ© Babessi	pecheur_12-2025_001	2025-12-18
257	individuel_Prod_Balikumbat	699253	individuel	f	0	0.00	en_attente	9	40	253	LocalitÃ© Balikumbat	indiv_12-2025_001	2025-12-18
258	coopÃ©rative_Prod_Ndop	699254	coopÃ©rative	f	0	0.00	en_attente	9	40	254	LocalitÃ© Ndop	coop_12-2025_001	2025-12-18
259	coopÃ©rative_Prod_Babadjou	699255	coopÃ©rative	f	0	0.00	en_attente	7	41	255	LocalitÃ© Babadjou	coop_12-2025_001	2025-12-18
260	autre_Prod_Batcham	699256	autre	f	0	0.00	en_attente	7	41	256	LocalitÃ© Batcham	autre_12-2025_001	2025-12-18
261	autre_Prod_Galim	699257	autre	f	0	0.00	en_attente	7	41	257	LocalitÃ© Galim	autre_12-2025_001	2025-12-18
262	alimentaire manufacture_Prod_Mbouda	699258	alimentaire manufacture	f	0	0.00	en_attente	7	41	258	LocalitÃ© Mbouda	alim_12-2025_001	2025-12-18
263	artisan_Prod_Bafang	699259	artisan	f	0	0.00	en_attente	7	42	259	LocalitÃ© Bafang	artisan_12-2025_001	2025-12-18
264	autre_Prod_Bakou	699260	autre	f	0	0.00	en_attente	7	42	260	LocalitÃ© Bakou	autre_12-2025_001	2025-12-18
265	agriculteur_Prod_Bana	699261	agriculteur	f	0	0.00	en_attente	7	42	261	LocalitÃ© Bana	agri_12-2025_001	2025-12-18
266	individuel_Prod_Bandja	699262	individuel	f	0	0.00	en_attente	7	42	262	LocalitÃ© Bandja	indiv_12-2025_001	2025-12-18
267	pÃªcheur_Prod_Banka	699263	pÃªcheur	f	0	0.00	en_attente	7	42	263	LocalitÃ© Banka	pecheur_12-2025_001	2025-12-18
268	Ã©leveur_Prod_Banwa	699264	Ã©leveur	f	0	0.00	en_attente	7	42	264	LocalitÃ© Banwa	eleveur_12-2025_001	2025-12-18
269	autre_Prod_KÃ©kem	699265	autre	f	0	0.00	en_attente	7	42	265	LocalitÃ© KÃ©kem	autre_12-2025_001	2025-12-18
270	agriculteur_Prod_Baham	699266	agriculteur	f	0	0.00	en_attente	7	43	266	LocalitÃ© Baham	agri_12-2025_001	2025-12-18
271	coopÃ©rative_Prod_Bamendjou	699267	coopÃ©rative	f	0	0.00	en_attente	7	43	267	LocalitÃ© Bamendjou	coop_12-2025_001	2025-12-18
272	coopÃ©rative_Prod_Bangou	699268	coopÃ©rative	f	0	0.00	en_attente	7	43	268	LocalitÃ© Bangou	coop_12-2025_001	2025-12-18
273	pÃªcheur_Prod_BatiÃ©	699269	pÃªcheur	f	0	0.00	en_attente	7	43	269	LocalitÃ© BatiÃ©	pecheur_12-2025_001	2025-12-18
274	pÃªcheur_Prod_Bayangam	699270	pÃªcheur	f	0	0.00	en_attente	7	44	270	LocalitÃ© Bayangam	pecheur_12-2025_001	2025-12-18
275	Ã©leveur_Prod_Djebem	699271	Ã©leveur	f	0	0.00	en_attente	7	44	271	LocalitÃ© Djebem	eleveur_12-2025_001	2025-12-18
276	agriculteur_Prod_Poumougne	699272	agriculteur	f	0	0.00	en_attente	7	44	272	LocalitÃ© Poumougne	agri_12-2025_001	2025-12-18
277	Ã©leveur_Prod_Dschang	699273	Ã©leveur	f	0	0.00	en_attente	7	45	273	LocalitÃ© Dschang	eleveur_12-2025_001	2025-12-18
278	artisan_Prod_FokouÃ©	699274	artisan	f	0	0.00	en_attente	7	45	274	LocalitÃ© FokouÃ©	artisan_12-2025_001	2025-12-18
279	autre_Prod_Fongo-Tongo	699275	autre	f	0	0.00	en_attente	7	45	275	LocalitÃ© Fongo-Tongo	autre_12-2025_001	2025-12-18
280	Ã©leveur_Prod_Nkong-Ni	699276	Ã©leveur	f	0	0.00	en_attente	7	45	276	LocalitÃ© Nkong-Ni	eleveur_12-2025_001	2025-12-18
281	alimentaire manufacture_Prod_Penka-Michel	699277	alimentaire manufacture	f	0	0.00	en_attente	7	45	277	LocalitÃ© Penka-Michel	alim_12-2025_001	2025-12-18
282	individuel_Prod_Santchou	699278	individuel	f	0	0.00	en_attente	7	45	278	LocalitÃ© Santchou	indiv_12-2025_001	2025-12-18
283	alimentaire manufacture_Prod_Bafoussam I	699279	alimentaire manufacture	f	0	0.00	en_attente	7	46	279	LocalitÃ© Bafoussam I	alim_12-2025_001	2025-12-18
284	individuel_Prod_Bafoussam II	699280	individuel	f	0	0.00	en_attente	7	46	280	LocalitÃ© Bafoussam II	indiv_12-2025_001	2025-12-18
285	coopÃ©rative_Prod_Bafoussam III	699281	coopÃ©rative	f	0	0.00	en_attente	7	46	281	LocalitÃ© Bafoussam III	coop_12-2025_001	2025-12-18
286	Ã©leveur_Prod_BangangtÃ©	699282	Ã©leveur	f	0	0.00	en_attente	7	47	282	LocalitÃ© BangangtÃ©	eleveur_12-2025_001	2025-12-18
287	artisan_Prod_Bassamba	699283	artisan	f	0	0.00	en_attente	7	47	283	LocalitÃ© Bassamba	artisan_12-2025_001	2025-12-18
288	alimentaire manufacture_Prod_Bazou	699284	alimentaire manufacture	f	0	0.00	en_attente	7	47	284	LocalitÃ© Bazou	alim_12-2025_001	2025-12-18
289	pÃªcheur_Prod_Tonga	699285	pÃªcheur	f	0	0.00	en_attente	7	47	285	LocalitÃ© Tonga	pecheur_12-2025_001	2025-12-18
290	agriculteur_Prod_Bangourain	699286	agriculteur	f	0	0.00	en_attente	7	48	286	LocalitÃ© Bangourain	agri_12-2025_001	2025-12-18
291	pÃªcheur_Prod_Foumban	699287	pÃªcheur	f	0	0.00	en_attente	7	48	287	LocalitÃ© Foumban	pecheur_12-2025_001	2025-12-18
292	Ã©leveur_Prod_Foumbot	699288	Ã©leveur	f	0	0.00	en_attente	7	48	288	LocalitÃ© Foumbot	eleveur_12-2025_001	2025-12-18
293	artisan_Prod_Kouoptamo	699289	artisan	f	0	0.00	en_attente	7	48	289	LocalitÃ© Kouoptamo	artisan_12-2025_001	2025-12-18
294	agriculteur_Prod_Koutaba	699290	agriculteur	f	0	0.00	en_attente	7	48	290	LocalitÃ© Koutaba	agri_12-2025_001	2025-12-18
295	autre_Prod_Magba	699291	autre	f	0	0.00	en_attente	7	48	291	LocalitÃ© Magba	autre_12-2025_001	2025-12-18
296	coopÃ©rative_Prod_Malentouen	699292	coopÃ©rative	f	0	0.00	en_attente	7	48	292	LocalitÃ© Malentouen	coop_12-2025_001	2025-12-18
297	coopÃ©rative_Prod_Massangam	699293	coopÃ©rative	f	0	0.00	en_attente	7	48	293	LocalitÃ© Massangam	coop_12-2025_001	2025-12-18
298	agriculteur_Prod_Njimom	699294	agriculteur	f	0	0.00	en_attente	7	48	294	LocalitÃ© Njimom	agri_12-2025_001	2025-12-18
299	Ã©leveur_Prod_Bengbis	699295	Ã©leveur	f	0	0.00	en_attente	8	49	295	LocalitÃ© Bengbis	eleveur_12-2025_001	2025-12-18
300	alimentaire manufacture_Prod_Djoum	699296	alimentaire manufacture	f	0	0.00	en_attente	8	49	296	LocalitÃ© Djoum	alim_12-2025_001	2025-12-18
301	individuel_Prod_Meyomessala	699297	individuel	f	0	0.00	en_attente	8	49	297	LocalitÃ© Meyomessala	indiv_12-2025_001	2025-12-18
302	Ã©leveur_Prod_Meyomessi	699298	Ã©leveur	f	0	0.00	en_attente	8	49	298	LocalitÃ© Meyomessi	eleveur_12-2025_001	2025-12-18
303	artisan_Prod_Mintom	699299	artisan	f	0	0.00	en_attente	8	49	299	LocalitÃ© Mintom	artisan_12-2025_001	2025-12-18
304	agriculteur_Prod_Oveng	699300	agriculteur	f	0	0.00	en_attente	8	49	300	LocalitÃ© Oveng	agri_12-2025_001	2025-12-18
305	individuel_Prod_SangmÃ©lima	699301	individuel	f	0	0.00	en_attente	8	49	301	LocalitÃ© SangmÃ©lima	indiv_12-2025_001	2025-12-18
306	individuel_Prod_ZoÃ©tÃ©lÃ©	699302	individuel	f	0	0.00	en_attente	8	49	302	LocalitÃ© ZoÃ©tÃ©lÃ©	indiv_12-2025_001	2025-12-18
307	alimentaire manufacture_Prod_Biwong-Bane	699303	alimentaire manufacture	f	0	0.00	en_attente	8	50	303	LocalitÃ© Biwong-Bane	alim_12-2025_001	2025-12-18
308	Ã©leveur_Prod_Biwong-Bulu	699304	Ã©leveur	f	0	0.00	en_attente	8	50	304	LocalitÃ© Biwong-Bulu	eleveur_12-2025_001	2025-12-18
309	pÃªcheur_Prod_Ebolowa I	699305	pÃªcheur	f	0	0.00	en_attente	8	50	305	LocalitÃ© Ebolowa I	pecheur_12-2025_001	2025-12-18
310	Ã©leveur_Prod_Ebolowa II	699306	Ã©leveur	f	0	0.00	en_attente	8	50	306	LocalitÃ© Ebolowa II	eleveur_12-2025_001	2025-12-18
311	autre_Prod_Efoulan	699307	autre	f	0	0.00	en_attente	8	50	307	LocalitÃ© Efoulan	autre_12-2025_001	2025-12-18
312	artisan_Prod_Mengong	699308	artisan	f	0	0.00	en_attente	8	50	308	LocalitÃ© Mengong	artisan_12-2025_001	2025-12-18
313	alimentaire manufacture_Prod_Mvangan	699309	alimentaire manufacture	f	0	0.00	en_attente	8	50	309	LocalitÃ© Mvangan	alim_12-2025_001	2025-12-18
314	Ã©leveur_Prod_Ngoulemakong	699310	Ã©leveur	f	0	0.00	en_attente	8	50	310	LocalitÃ© Ngoulemakong	eleveur_12-2025_001	2025-12-18
315	individuel_Prod_Akom II	699311	individuel	f	0	0.00	en_attente	8	51	311	LocalitÃ© Akom II	indiv_12-2025_001	2025-12-18
316	alimentaire manufacture_Prod_Bipindi	699312	alimentaire manufacture	f	0	0.00	en_attente	8	51	312	LocalitÃ© Bipindi	alim_12-2025_001	2025-12-18
317	coopÃ©rative_Prod_Campo	699313	coopÃ©rative	f	0	0.00	en_attente	8	51	313	LocalitÃ© Campo	coop_12-2025_001	2025-12-18
318	coopÃ©rative_Prod_Kribi I	699314	coopÃ©rative	f	0	0.00	en_attente	8	51	314	LocalitÃ© Kribi I	coop_12-2025_001	2025-12-18
319	Ã©leveur_Prod_Kribi II	699315	Ã©leveur	f	0	0.00	en_attente	8	51	315	LocalitÃ© Kribi II	eleveur_12-2025_001	2025-12-18
320	Ã©leveur_Prod_Lokoundje	699316	Ã©leveur	f	0	0.00	en_attente	8	51	316	LocalitÃ© Lokoundje	eleveur_12-2025_001	2025-12-18
321	agriculteur_Prod_Lolodorf	699317	agriculteur	f	0	0.00	en_attente	8	51	317	LocalitÃ© Lolodorf	agri_12-2025_001	2025-12-18
322	pÃªcheur_Prod_Mvengue	699318	pÃªcheur	f	0	0.00	en_attente	8	51	318	LocalitÃ© Mvengue	pecheur_12-2025_001	2025-12-18
323	individuel_Prod_Niete	699319	individuel	f	0	0.00	en_attente	8	51	319	LocalitÃ© Niete	indiv_12-2025_001	2025-12-18
324	alimentaire manufacture_Prod_Ambam	699320	alimentaire manufacture	f	0	0.00	en_attente	8	52	320	LocalitÃ© Ambam	alim_12-2025_001	2025-12-18
325	artisan_Prod_KyÃ©-Ossi	699321	artisan	f	0	0.00	en_attente	8	52	321	LocalitÃ© KyÃ©-Ossi	artisan_12-2025_001	2025-12-18
326	agriculteur_Prod_Ma'an	699322	agriculteur	f	0	0.00	en_attente	8	52	322	LocalitÃ© Ma'an	agri_12-2025_001	2025-12-18
327	autre_Prod_Olamze	699323	autre	f	0	0.00	en_attente	8	52	323	LocalitÃ© Olamze	autre_12-2025_001	2025-12-18
328	autre_Prod_Buea	699324	autre	f	0	0.00	en_attente	10	53	324	LocalitÃ© Buea	autre_12-2025_001	2025-12-18
329	pÃªcheur_Prod_LimbÃ© I	699325	pÃªcheur	f	0	0.00	en_attente	10	53	325	LocalitÃ© LimbÃ© I	pecheur_12-2025_001	2025-12-18
330	artisan_Prod_LimbÃ© II	699326	artisan	f	0	0.00	en_attente	10	53	326	LocalitÃ© LimbÃ© II	artisan_12-2025_001	2025-12-18
331	Ã©leveur_Prod_LimbÃ© III	699327	Ã©leveur	f	0	0.00	en_attente	10	53	327	LocalitÃ© LimbÃ© III	eleveur_12-2025_001	2025-12-18
332	agriculteur_Prod_Muyuka	699328	agriculteur	f	0	0.00	en_attente	10	53	328	LocalitÃ© Muyuka	agri_12-2025_001	2025-12-18
333	alimentaire manufacture_Prod_Tiko	699329	alimentaire manufacture	f	0	0.00	en_attente	10	53	329	LocalitÃ© Tiko	alim_12-2025_001	2025-12-18
334	Ã©leveur_Prod_West Coast	699330	Ã©leveur	f	0	0.00	en_attente	10	53	330	LocalitÃ© West Coast	eleveur_12-2025_001	2025-12-18
335	autre_Prod_Bangem	699331	autre	f	0	0.00	en_attente	10	54	331	LocalitÃ© Bangem	autre_12-2025_001	2025-12-18
336	autre_Prod_Nguti	699332	autre	f	0	0.00	en_attente	10	54	332	LocalitÃ© Nguti	autre_12-2025_001	2025-12-18
337	pÃªcheur_Prod_Tombel	699333	pÃªcheur	f	0	0.00	en_attente	10	54	333	LocalitÃ© Tombel	pecheur_12-2025_001	2025-12-18
338	autre_Prod_Alou	699334	autre	f	0	0.00	en_attente	10	55	334	LocalitÃ© Alou	autre_12-2025_001	2025-12-18
339	individuel_Prod_Fontem	699335	individuel	f	0	0.00	en_attente	10	55	335	LocalitÃ© Fontem	indiv_12-2025_001	2025-12-18
340	autre_Prod_Wabane	699336	autre	f	0	0.00	en_attente	10	55	336	LocalitÃ© Wabane	autre_12-2025_001	2025-12-18
341	individuel_Prod_Akwaya	699337	individuel	f	0	0.00	en_attente	10	56	337	LocalitÃ© Akwaya	indiv_12-2025_001	2025-12-18
342	Ã©leveur_Prod_Eyumodjock	699338	Ã©leveur	f	0	0.00	en_attente	10	56	338	LocalitÃ© Eyumodjock	eleveur_12-2025_001	2025-12-18
343	individuel_Prod_MamfÃ© Central	699339	individuel	f	0	0.00	en_attente	10	56	339	LocalitÃ© MamfÃ© Central	indiv_12-2025_001	2025-12-18
344	alimentaire manufacture_Prod_Upper Banyang	699340	alimentaire manufacture	f	0	0.00	en_attente	10	56	340	LocalitÃ© Upper Banyang	alim_12-2025_001	2025-12-18
345	agriculteur_Prod_Konye	699341	agriculteur	f	0	0.00	en_attente	10	57	341	LocalitÃ© Konye	agri_12-2025_001	2025-12-18
346	alimentaire manufacture_Prod_Kumba I	699342	alimentaire manufacture	f	0	0.00	en_attente	10	57	342	LocalitÃ© Kumba I	alim_12-2025_001	2025-12-18
347	pÃªcheur_Prod_Kumba II	699343	pÃªcheur	f	0	0.00	en_attente	10	57	343	LocalitÃ© Kumba II	pecheur_12-2025_001	2025-12-18
348	artisan_Prod_Kumba III	699344	artisan	f	0	0.00	en_attente	10	57	344	LocalitÃ© Kumba III	artisan_12-2025_001	2025-12-18
349	artisan_Prod_Mbonge	699345	artisan	f	0	0.00	en_attente	10	57	345	LocalitÃ© Mbonge	artisan_12-2025_001	2025-12-18
351	artisan_Prod_Dikome-Balue	699347	artisan	f	0	0.00	en_attente	10	58	347	LocalitÃ© Dikome-Balue	artisan_12-2025_001	2025-12-18
352	alimentaire manufacture_Prod_Ekondo-Titi	699348	alimentaire manufacture	f	0	0.00	en_attente	10	58	348	LocalitÃ© Ekondo-Titi	alim_12-2025_001	2025-12-18
353	pÃªcheur_Prod_Idabato	699349	pÃªcheur	f	0	0.00	en_attente	10	58	349	LocalitÃ© Idabato	pecheur_12-2025_001	2025-12-18
354	coopÃ©rative_Prod_Isanguele	699350	coopÃ©rative	f	0	0.00	en_attente	10	58	350	LocalitÃ© Isanguele	coop_12-2025_001	2025-12-18
350	individuel_Prod_Bamusso	699346	individuel	f	0	3930.00	en_attente	10	58	346	LocalitÃ© Bamusso	indiv_12-2025_002	2025-12-18
359	AJ BEA BEA NGIDJOI	+237670841023	\N	f	0	0.00	actif	\N	\N	\N	\N	autre_12-2025_001	2025-12-24
362	Bea Ngidjoi Augustin	699888663	individuel	t	0	0.00	actif	1	13	77	Mandoga	indiv_12-2025_001	2025-12-26
363	Transfert Interne	000000000	\N	f	0	0.00	actif	\N	\N	\N	\N	autre_01-2026_001	2026-01-18
\.


--
-- Data for Name: quality_coeff; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."quality_coeff" ("qual", "coef") FROM stdin;
A	1.0000
B	0.9500
C	0.9000
D	0.8500
\.


--
-- Data for Name: realized_gains; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."realized_gains" ("id", "lot_id", "virtual_revenue_id", "amount", "details", "created_at", "gross_amount", "tax_amount", "net_amount") FROM stdin;
\.


--
-- Data for Name: regions; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."regions" ("id", "nom") FROM stdin;
1	Centre
2	Littoral
3	Nord
4	Extrême-Nord
5	Adamaoua
6	Est
7	Ouest
8	Sud
9	Nord-Ouest
10	Sud-Ouest
\.


--
-- Data for Name: retraits; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."retraits" ("id", "lot_id", "utilisateur", "type_retrait", "quantite", "unite", "prix_ref", "valeur_totale", "date_sortie", "destination_producteur_id", "montant_du", "mode_paiement", "points_utilises", "statut_paiement", "destination_client", "destination_magasin_id", "motif", "magasin_id", "coef_qualite", "taux_tax", "region_id", "departement_id", "arrondissement_id", "localite", "admission_id") FROM stdin;
1	5	superadmin	client	5.00	g	500.00	2500.00	2025-12-22 13:28:56.282676	\N	\N	liquide	\N	comptant	\N	\N	\N	1	\N	\N	\N	\N	\N	\N	10
10	5	superadmin	client	2.00	g	5000.00	\N	2026-01-14 22:59:17.978623	\N	\N	\N	\N	\N	\N	\N	\N	1	\N	\N	\N	\N	\N	\N	\N
19	15	superadmin	client	450.00	litres	1400.00	\N	2026-01-15 00:23:13.623802	\N	\N	\N	\N	\N	\N	\N	\N	1	\N	\N	\N	\N	\N	\N	\N
20	18	superadmin	client	4000.00	unites	4500.00	\N	2026-01-15 00:23:39.322109	\N	\N	\N	\N	\N	\N	\N	\N	19	\N	\N	\N	\N	\N	\N	\N
21	10	ndjomfils	client	25.00	kg	2500.00	\N	2026-01-16 16:42:55.034217	\N	\N	\N	\N	\N	\N	\N	\N	2	\N	\N	\N	\N	\N	\N	\N
22	10	ndjomfils	client	25.00	kg	2500.00	\N	2026-01-16 16:42:55.159872	\N	\N	\N	\N	\N	\N	\N	\N	2	\N	\N	\N	\N	\N	\N	\N
25	15	superadmin	client	120.00	litres	1400.00	\N	2026-01-18 11:53:22.459853	\N	\N	\N	\N	\N	\N	\N	\N	1	\N	\N	\N	\N	\N	\N	\N
31	5	superadmin	magasin	47.00	g	5000.00	\N	2026-01-18 13:27:11.838263	\N	\N	\N	\N	\N	\N	16	Transfert vers magasin 16. Chauffeur: chauffeur_Nom01_CE01 (chauffeur_12-2025_001) - 69901001 (ID: CE01_chauffeur_001). 	1	\N	\N	\N	\N	\N	\N	\N
32	15	superadmin	magasin	75.00	litres	1400.00	\N	2026-01-23 01:18:55.687236	\N	\N	\N	\N	\N	\N	17	Transfert vers magasin 17. Chauffeur: chauffeur_Nom01_CE01 (chauffeur_12-2025_001) - 69901001 (ID: CE01_chauffeur_001). 	1	\N	\N	\N	\N	\N	\N	\N
33	17	superadmin	client	25.00	sacs	17850.00	\N	2026-01-27 22:32:31.180985	\N	\N	\N	\N	\N	\N	\N	\N	19	\N	\N	\N	\N	\N	\N	\N
34	6	superadmin	client	3200.00	kg	5000.00	\N	2026-01-27 22:32:57.597583	\N	\N	\N	\N	\N	\N	\N	\N	19	\N	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: tax_rates; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."tax_rates" ("category", "tax_rate") FROM stdin;
frais	0.2500
court	0.2500
secs	0.1000
manualim	0.1000
nonalim	0.1000
sensible	0.2500
\.


--
-- Data for Name: transferts; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."transferts" ("id", "lot_id", "magasin_depart", "magasin_destination", "chauffeur_id", "quantite", "unite", "prix_ref", "statut", "motif", "utilisateur", "date_creation", "date_reception", "validation_auditeur") FROM stdin;
\.


--
-- Data for Name: transferts_urgence; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."transferts_urgence" ("id", "lot_id", "magasin_id_depart", "magasin_id_dest", "quantite", "chauffeur", "motif_urgence", "admin_local_depart_ok", "admin_local_dest_ok", "audit_final_ok", "statut", "date_creation", "auditeur_id") FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."users" ("id", "username", "password_hash", "role", "magasin_id", "prenom", "nom", "email", "telephone", "created_at", "last_login", "statut", "avatar_url", "matricule") FROM stdin;
CE01_admin_001	CE01_admin_01	hash-admin-CE01-1	admin	1	admin_Prenom1	admin_NomCE01	admin1.CE01@nfbo.local	69001001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
CE01_admin_002	CE01_admin_02	hash-admin-CE01-2	admin	1	admin_Prenom2	admin_NomCE01	admin2.CE01@nfbo.local	69001002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
CE02_admin_001	CE02_admin_01	hash-admin-CE02-1	admin	2	admin_Prenom1	admin_NomCE02	admin1.CE02@nfbo.local	69002001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
CE02_admin_002	CE02_admin_02	hash-admin-CE02-2	admin	2	admin_Prenom2	admin_NomCE02	admin2.CE02@nfbo.local	69002002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
LT01_admin_001	LT01_admin_01	hash-admin-LT01-1	admin	3	admin_Prenom1	admin_NomLT01	admin1.LT01@nfbo.local	69003001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
LT01_admin_002	LT01_admin_02	hash-admin-LT01-2	admin	3	admin_Prenom2	admin_NomLT01	admin2.LT01@nfbo.local	69003002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
LT02_admin_001	LT02_admin_01	hash-admin-LT02-1	admin	4	admin_Prenom1	admin_NomLT02	admin1.LT02@nfbo.local	69004001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
LT02_admin_002	LT02_admin_02	hash-admin-LT02-2	admin	4	admin_Prenom2	admin_NomLT02	admin2.LT02@nfbo.local	69004002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
NO01_admin_001	NO01_admin_01	hash-admin-NO01-1	admin	5	admin_Prenom1	admin_NomNO01	admin1.NO01@nfbo.local	69005001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
NO01_admin_002	NO01_admin_02	hash-admin-NO01-2	admin	5	admin_Prenom2	admin_NomNO01	admin2.NO01@nfbo.local	69005002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
NO02_admin_001	NO02_admin_01	hash-admin-NO02-1	admin	6	admin_Prenom1	admin_NomNO02	admin1.NO02@nfbo.local	69006001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
NO02_admin_002	NO02_admin_02	hash-admin-NO02-2	admin	6	admin_Prenom2	admin_NomNO02	admin2.NO02@nfbo.local	69006002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
EN01_admin_001	EN01_admin_01	hash-admin-EN01-1	admin	7	admin_Prenom1	admin_NomEN01	admin1.EN01@nfbo.local	69007001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
EN01_admin_002	EN01_admin_02	hash-admin-EN01-2	admin	7	admin_Prenom2	admin_NomEN01	admin2.EN01@nfbo.local	69007002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
EN02_admin_001	EN02_admin_01	hash-admin-EN02-1	admin	8	admin_Prenom1	admin_NomEN02	admin1.EN02@nfbo.local	69008001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
EN02_admin_002	EN02_admin_02	hash-admin-EN02-2	admin	8	admin_Prenom2	admin_NomEN02	admin2.EN02@nfbo.local	69008002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
AD01_admin_001	AD01_admin_01	hash-admin-AD01-1	admin	9	admin_Prenom1	admin_NomAD01	admin1.AD01@nfbo.local	69009001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
AD01_admin_002	AD01_admin_02	hash-admin-AD01-2	admin	9	admin_Prenom2	admin_NomAD01	admin2.AD01@nfbo.local	69009002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
AD02_admin_001	AD02_admin_01	hash-admin-AD02-1	admin	10	admin_Prenom1	admin_NomAD02	admin1.AD02@nfbo.local	69010001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
AD02_admin_002	AD02_admin_02	hash-admin-AD02-2	admin	10	admin_Prenom2	admin_NomAD02	admin2.AD02@nfbo.local	69010002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
ES01_admin_001	ES01_admin_01	hash-admin-ES01-1	admin	11	admin_Prenom1	admin_NomES01	admin1.ES01@nfbo.local	69011001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
ES01_admin_002	ES01_admin_02	hash-admin-ES01-2	admin	11	admin_Prenom2	admin_NomES01	admin2.ES01@nfbo.local	69011002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
ES02_admin_001	ES02_admin_01	hash-admin-ES02-1	admin	12	admin_Prenom1	admin_NomES02	admin1.ES02@nfbo.local	69012001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
ES02_admin_002	ES02_admin_02	hash-admin-ES02-2	admin	12	admin_Prenom2	admin_NomES02	admin2.ES02@nfbo.local	69012002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
OU01_admin_001	OU01_admin_01	hash-admin-OU01-1	admin	13	admin_Prenom1	admin_NomOU01	admin1.OU01@nfbo.local	69013001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
OU01_admin_002	OU01_admin_02	hash-admin-OU01-2	admin	13	admin_Prenom2	admin_NomOU01	admin2.OU01@nfbo.local	69013002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
OU02_admin_001	OU02_admin_01	hash-admin-OU02-1	admin	14	admin_Prenom1	admin_NomOU02	admin1.OU02@nfbo.local	69014001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
OU02_admin_002	OU02_admin_02	hash-admin-OU02-2	admin	14	admin_Prenom2	admin_NomOU02	admin2.OU02@nfbo.local	69014002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
SU01_admin_001	SU01_admin_01	hash-admin-SU01-1	admin	15	admin_Prenom1	admin_NomSU01	admin1.SU01@nfbo.local	69015001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
SU01_admin_002	SU01_admin_02	hash-admin-SU01-2	admin	15	admin_Prenom2	admin_NomSU01	admin2.SU01@nfbo.local	69015002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
SU02_admin_001	SU02_admin_01	hash-admin-SU02-1	admin	16	admin_Prenom1	admin_NomSU02	admin1.SU02@nfbo.local	69016001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
SU02_admin_002	SU02_admin_02	hash-admin-SU02-2	admin	16	admin_Prenom2	admin_NomSU02	admin2.SU02@nfbo.local	69016002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
NW01_admin_001	NW01_admin_01	hash-admin-NW01-1	admin	17	admin_Prenom1	admin_NomNW01	admin1.NW01@nfbo.local	69017001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
NW01_admin_002	NW01_admin_02	hash-admin-NW01-2	admin	17	admin_Prenom2	admin_NomNW01	admin2.NW01@nfbo.local	69017002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
NW02_admin_001	NW02_admin_01	hash-admin-NW02-1	admin	18	admin_Prenom1	admin_NomNW02	admin1.NW02@nfbo.local	69018001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
NW02_admin_002	NW02_admin_02	hash-admin-NW02-2	admin	18	admin_Prenom2	admin_NomNW02	admin2.NW02@nfbo.local	69018002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
SW01_admin_001	SW01_admin_01	hash-admin-SW01-1	admin	19	admin_Prenom1	admin_NomSW01	admin1.SW01@nfbo.local	69019001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
SW01_admin_002	SW01_admin_02	hash-admin-SW01-2	admin	19	admin_Prenom2	admin_NomSW01	admin2.SW01@nfbo.local	69019002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
SW02_admin_001	SW02_admin_01	hash-admin-SW02-1	admin	20	admin_Prenom1	admin_NomSW02	admin1.SW02@nfbo.local	69020001	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_001
SW02_admin_002	SW02_admin_02	hash-admin-SW02-2	admin	20	admin_Prenom2	admin_NomSW02	admin2.SW02@nfbo.local	69020002	2025-12-18 13:27:54.701642	\N	actif	\N	admin_12-2025_002
CE01_caisse_001	CE01_caisse_01	hash-caisse-CE01-1	caisse	1	caisse_Prenom1	caisse_NomCE01	caisse1.CE01@nfbo.local	69001001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
CE01_caisse_002	CE01_caisse_02	hash-caisse-CE01-2	caisse	1	caisse_Prenom2	caisse_NomCE01	caisse2.CE01@nfbo.local	69001002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
CE02_caisse_001	CE02_caisse_01	hash-caisse-CE02-1	caisse	2	caisse_Prenom1	caisse_NomCE02	caisse1.CE02@nfbo.local	69002001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
CE02_caisse_002	CE02_caisse_02	hash-caisse-CE02-2	caisse	2	caisse_Prenom2	caisse_NomCE02	caisse2.CE02@nfbo.local	69002002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
LT01_caisse_001	LT01_caisse_01	hash-caisse-LT01-1	caisse	3	caisse_Prenom1	caisse_NomLT01	caisse1.LT01@nfbo.local	69003001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
LT01_caisse_002	LT01_caisse_02	hash-caisse-LT01-2	caisse	3	caisse_Prenom2	caisse_NomLT01	caisse2.LT01@nfbo.local	69003002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
LT02_caisse_001	LT02_caisse_01	hash-caisse-LT02-1	caisse	4	caisse_Prenom1	caisse_NomLT02	caisse1.LT02@nfbo.local	69004001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
LT02_caisse_002	LT02_caisse_02	hash-caisse-LT02-2	caisse	4	caisse_Prenom2	caisse_NomLT02	caisse2.LT02@nfbo.local	69004002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
NO01_caisse_001	NO01_caisse_01	hash-caisse-NO01-1	caisse	5	caisse_Prenom1	caisse_NomNO01	caisse1.NO01@nfbo.local	69005001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
NO01_caisse_002	NO01_caisse_02	hash-caisse-NO01-2	caisse	5	caisse_Prenom2	caisse_NomNO01	caisse2.NO01@nfbo.local	69005002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
NO02_caisse_001	NO02_caisse_01	hash-caisse-NO02-1	caisse	6	caisse_Prenom1	caisse_NomNO02	caisse1.NO02@nfbo.local	69006001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
NO02_caisse_002	NO02_caisse_02	hash-caisse-NO02-2	caisse	6	caisse_Prenom2	caisse_NomNO02	caisse2.NO02@nfbo.local	69006002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
EN01_caisse_001	EN01_caisse_01	hash-caisse-EN01-1	caisse	7	caisse_Prenom1	caisse_NomEN01	caisse1.EN01@nfbo.local	69007001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
EN01_caisse_002	EN01_caisse_02	hash-caisse-EN01-2	caisse	7	caisse_Prenom2	caisse_NomEN01	caisse2.EN01@nfbo.local	69007002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
EN02_caisse_001	EN02_caisse_01	hash-caisse-EN02-1	caisse	8	caisse_Prenom1	caisse_NomEN02	caisse1.EN02@nfbo.local	69008001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
EN02_caisse_002	EN02_caisse_02	hash-caisse-EN02-2	caisse	8	caisse_Prenom2	caisse_NomEN02	caisse2.EN02@nfbo.local	69008002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
AD01_caisse_001	AD01_caisse_01	hash-caisse-AD01-1	caisse	9	caisse_Prenom1	caisse_NomAD01	caisse1.AD01@nfbo.local	69009001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
AD01_caisse_002	AD01_caisse_02	hash-caisse-AD01-2	caisse	9	caisse_Prenom2	caisse_NomAD01	caisse2.AD01@nfbo.local	69009002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
AD02_caisse_001	AD02_caisse_01	hash-caisse-AD02-1	caisse	10	caisse_Prenom1	caisse_NomAD02	caisse1.AD02@nfbo.local	69010001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
AD02_caisse_002	AD02_caisse_02	hash-caisse-AD02-2	caisse	10	caisse_Prenom2	caisse_NomAD02	caisse2.AD02@nfbo.local	69010002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
ES01_caisse_001	ES01_caisse_01	hash-caisse-ES01-1	caisse	11	caisse_Prenom1	caisse_NomES01	caisse1.ES01@nfbo.local	69011001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
ES01_caisse_002	ES01_caisse_02	hash-caisse-ES01-2	caisse	11	caisse_Prenom2	caisse_NomES01	caisse2.ES01@nfbo.local	69011002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
ES02_caisse_001	ES02_caisse_01	hash-caisse-ES02-1	caisse	12	caisse_Prenom1	caisse_NomES02	caisse1.ES02@nfbo.local	69012001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
ES02_caisse_002	ES02_caisse_02	hash-caisse-ES02-2	caisse	12	caisse_Prenom2	caisse_NomES02	caisse2.ES02@nfbo.local	69012002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
OU01_caisse_001	OU01_caisse_01	hash-caisse-OU01-1	caisse	13	caisse_Prenom1	caisse_NomOU01	caisse1.OU01@nfbo.local	69013001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
OU01_caisse_002	OU01_caisse_02	hash-caisse-OU01-2	caisse	13	caisse_Prenom2	caisse_NomOU01	caisse2.OU01@nfbo.local	69013002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
OU02_caisse_001	OU02_caisse_01	hash-caisse-OU02-1	caisse	14	caisse_Prenom1	caisse_NomOU02	caisse1.OU02@nfbo.local	69014001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
OU02_caisse_002	OU02_caisse_02	hash-caisse-OU02-2	caisse	14	caisse_Prenom2	caisse_NomOU02	caisse2.OU02@nfbo.local	69014002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
SU01_caisse_001	SU01_caisse_01	hash-caisse-SU01-1	caisse	15	caisse_Prenom1	caisse_NomSU01	caisse1.SU01@nfbo.local	69015001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
SU01_caisse_002	SU01_caisse_02	hash-caisse-SU01-2	caisse	15	caisse_Prenom2	caisse_NomSU01	caisse2.SU01@nfbo.local	69015002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
SU02_caisse_001	SU02_caisse_01	hash-caisse-SU02-1	caisse	16	caisse_Prenom1	caisse_NomSU02	caisse1.SU02@nfbo.local	69016001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
SU02_caisse_002	SU02_caisse_02	hash-caisse-SU02-2	caisse	16	caisse_Prenom2	caisse_NomSU02	caisse2.SU02@nfbo.local	69016002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
NW01_caisse_001	NW01_caisse_01	hash-caisse-NW01-1	caisse	17	caisse_Prenom1	caisse_NomNW01	caisse1.NW01@nfbo.local	69017001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
NW01_caisse_002	NW01_caisse_02	hash-caisse-NW01-2	caisse	17	caisse_Prenom2	caisse_NomNW01	caisse2.NW01@nfbo.local	69017002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
NW02_caisse_001	NW02_caisse_01	hash-caisse-NW02-1	caisse	18	caisse_Prenom1	caisse_NomNW02	caisse1.NW02@nfbo.local	69018001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
NW02_caisse_002	NW02_caisse_02	hash-caisse-NW02-2	caisse	18	caisse_Prenom2	caisse_NomNW02	caisse2.NW02@nfbo.local	69018002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
SW01_caisse_001	SW01_caisse_01	hash-caisse-SW01-1	caisse	19	caisse_Prenom1	caisse_NomSW01	caisse1.SW01@nfbo.local	69019001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
SW01_caisse_002	SW01_caisse_02	hash-caisse-SW01-2	caisse	19	caisse_Prenom2	caisse_NomSW01	caisse2.SW01@nfbo.local	69019002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
SW02_caisse_001	SW02_caisse_01	hash-caisse-SW02-1	caisse	20	caisse_Prenom1	caisse_NomSW02	caisse1.SW02@nfbo.local	69020001	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_001
SW02_caisse_002	SW02_caisse_02	hash-caisse-SW02-2	caisse	20	caisse_Prenom2	caisse_NomSW02	caisse2.SW02@nfbo.local	69020002	2025-12-18 13:27:54.701642	\N	actif	\N	caisse_12-2025_002
CE01_stock_001	CE01_stock_01	hash-stock-CE01-1	stock	1	stock_Prenom1	stock_NomCE01	stock1.CE01@nfbo.local	69001001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
CE01_stock_002	CE01_stock_02	hash-stock-CE01-2	stock	1	stock_Prenom2	stock_NomCE01	stock2.CE01@nfbo.local	69001002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
CE02_stock_001	CE02_stock_01	hash-stock-CE02-1	stock	2	stock_Prenom1	stock_NomCE02	stock1.CE02@nfbo.local	69002001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
CE02_stock_002	CE02_stock_02	hash-stock-CE02-2	stock	2	stock_Prenom2	stock_NomCE02	stock2.CE02@nfbo.local	69002002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
LT01_stock_001	LT01_stock_01	hash-stock-LT01-1	stock	3	stock_Prenom1	stock_NomLT01	stock1.LT01@nfbo.local	69003001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
LT01_stock_002	LT01_stock_02	hash-stock-LT01-2	stock	3	stock_Prenom2	stock_NomLT01	stock2.LT01@nfbo.local	69003002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
LT02_stock_001	LT02_stock_01	hash-stock-LT02-1	stock	4	stock_Prenom1	stock_NomLT02	stock1.LT02@nfbo.local	69004001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
LT02_stock_002	LT02_stock_02	hash-stock-LT02-2	stock	4	stock_Prenom2	stock_NomLT02	stock2.LT02@nfbo.local	69004002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
NO01_stock_001	NO01_stock_01	hash-stock-NO01-1	stock	5	stock_Prenom1	stock_NomNO01	stock1.NO01@nfbo.local	69005001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
NO01_stock_002	NO01_stock_02	hash-stock-NO01-2	stock	5	stock_Prenom2	stock_NomNO01	stock2.NO01@nfbo.local	69005002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
NO02_stock_001	NO02_stock_01	hash-stock-NO02-1	stock	6	stock_Prenom1	stock_NomNO02	stock1.NO02@nfbo.local	69006001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
NO02_stock_002	NO02_stock_02	hash-stock-NO02-2	stock	6	stock_Prenom2	stock_NomNO02	stock2.NO02@nfbo.local	69006002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
EN01_stock_001	EN01_stock_01	hash-stock-EN01-1	stock	7	stock_Prenom1	stock_NomEN01	stock1.EN01@nfbo.local	69007001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
EN01_stock_002	EN01_stock_02	hash-stock-EN01-2	stock	7	stock_Prenom2	stock_NomEN01	stock2.EN01@nfbo.local	69007002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
EN02_stock_001	EN02_stock_01	hash-stock-EN02-1	stock	8	stock_Prenom1	stock_NomEN02	stock1.EN02@nfbo.local	69008001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
EN02_stock_002	EN02_stock_02	hash-stock-EN02-2	stock	8	stock_Prenom2	stock_NomEN02	stock2.EN02@nfbo.local	69008002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
AD01_stock_001	AD01_stock_01	hash-stock-AD01-1	stock	9	stock_Prenom1	stock_NomAD01	stock1.AD01@nfbo.local	69009001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
AD01_stock_002	AD01_stock_02	hash-stock-AD01-2	stock	9	stock_Prenom2	stock_NomAD01	stock2.AD01@nfbo.local	69009002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
AD02_stock_001	AD02_stock_01	hash-stock-AD02-1	stock	10	stock_Prenom1	stock_NomAD02	stock1.AD02@nfbo.local	69010001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
AD02_stock_002	AD02_stock_02	hash-stock-AD02-2	stock	10	stock_Prenom2	stock_NomAD02	stock2.AD02@nfbo.local	69010002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
ES01_stock_001	ES01_stock_01	hash-stock-ES01-1	stock	11	stock_Prenom1	stock_NomES01	stock1.ES01@nfbo.local	69011001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
ES01_stock_002	ES01_stock_02	hash-stock-ES01-2	stock	11	stock_Prenom2	stock_NomES01	stock2.ES01@nfbo.local	69011002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
ES02_stock_001	ES02_stock_01	hash-stock-ES02-1	stock	12	stock_Prenom1	stock_NomES02	stock1.ES02@nfbo.local	69012001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
ES02_stock_002	ES02_stock_02	hash-stock-ES02-2	stock	12	stock_Prenom2	stock_NomES02	stock2.ES02@nfbo.local	69012002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
OU01_stock_001	OU01_stock_01	hash-stock-OU01-1	stock	13	stock_Prenom1	stock_NomOU01	stock1.OU01@nfbo.local	69013001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
OU01_stock_002	OU01_stock_02	hash-stock-OU01-2	stock	13	stock_Prenom2	stock_NomOU01	stock2.OU01@nfbo.local	69013002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
OU02_stock_001	OU02_stock_01	hash-stock-OU02-1	stock	14	stock_Prenom1	stock_NomOU02	stock1.OU02@nfbo.local	69014001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
OU02_stock_002	OU02_stock_02	hash-stock-OU02-2	stock	14	stock_Prenom2	stock_NomOU02	stock2.OU02@nfbo.local	69014002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
SU01_stock_001	SU01_stock_01	hash-stock-SU01-1	stock	15	stock_Prenom1	stock_NomSU01	stock1.SU01@nfbo.local	69015001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
SU01_stock_002	SU01_stock_02	hash-stock-SU01-2	stock	15	stock_Prenom2	stock_NomSU01	stock2.SU01@nfbo.local	69015002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
SU02_stock_001	SU02_stock_01	hash-stock-SU02-1	stock	16	stock_Prenom1	stock_NomSU02	stock1.SU02@nfbo.local	69016001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
SU02_stock_002	SU02_stock_02	hash-stock-SU02-2	stock	16	stock_Prenom2	stock_NomSU02	stock2.SU02@nfbo.local	69016002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
NW01_stock_001	NW01_stock_01	hash-stock-NW01-1	stock	17	stock_Prenom1	stock_NomNW01	stock1.NW01@nfbo.local	69017001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
NW01_stock_002	NW01_stock_02	hash-stock-NW01-2	stock	17	stock_Prenom2	stock_NomNW01	stock2.NW01@nfbo.local	69017002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
NW02_stock_001	NW02_stock_01	hash-stock-NW02-1	stock	18	stock_Prenom1	stock_NomNW02	stock1.NW02@nfbo.local	69018001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
NW02_stock_002	NW02_stock_02	hash-stock-NW02-2	stock	18	stock_Prenom2	stock_NomNW02	stock2.NW02@nfbo.local	69018002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
SW01_stock_001	SW01_stock_01	hash-stock-SW01-1	stock	19	stock_Prenom1	stock_NomSW01	stock1.SW01@nfbo.local	69019001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
SW01_stock_002	SW01_stock_02	hash-stock-SW01-2	stock	19	stock_Prenom2	stock_NomSW01	stock2.SW01@nfbo.local	69019002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
SW02_stock_001	SW02_stock_01	hash-stock-SW02-1	stock	20	stock_Prenom1	stock_NomSW02	stock1.SW02@nfbo.local	69020001	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_001
SW02_stock_002	SW02_stock_02	hash-stock-SW02-2	stock	20	stock_Prenom2	stock_NomSW02	stock2.SW02@nfbo.local	69020002	2025-12-18 13:27:54.701642	\N	actif	\N	stock_12-2025_002
CE01_superadmin_001	superadmin	$2a$06$xZTb.5RI9T0yvx72y51Y4OFIY3/UZduE1v2rZrbgMHY5Arpvj9Xaq	superadmin	1	Super	Admin	superadmin@nfbo.local	690000000	2025-12-18 18:46:51.621746	\N	actif	\N	superadmin_12-2025_001
SYS_superadmin_001	ndjomfils	$2a$06$kGjP8S6OtSZLRxHb.wbMP.7/B2Qq51gptolwyBEoXVxgVxYAK8i4O	superadmin	\N	Fils	Ndjom	ndjomolivier@yahoo.fr	677797754	2025-12-26 18:30:46.741783	\N	actif	\N	SUP_12-2025_001
SYS_auditeur_001	beabeangidjoi	$2a$06$1S/EBSmfFyPfXtpZbT0qnu7utSxfjiaWN9JYT9TsdAnwjk3sx2VFq	auditeur	\N	John	Doe	donpapyjoe@gmail.com	69797952	2025-12-27 01:19:13.817438	\N	actif	\N	AUD_12-2025_001
CE01_admin_003	testeur	$2a$06$.u9ObwyjfUOQ7oupXkGCZuJIgZpXaLuVpWExaWqIMk5QDihqMIltO	admin	1	testeur	testeur	testeur@test.eur	670717273	2025-12-27 01:23:01.804972	\N	actif	\N	ADM_12-2025_003
CE01_stock_003	Angel	$2a$06$tRw.OnZ/imM4fMLksL9n.uTEdU2YN5NjI41g5leTP6.SFCo65OUOy	stock	1	Angel	Ndjom	angiendjom@nbfo.coop	674669552	2025-12-28 00:24:44.556723	\N	actif	\N	STO_12-2025_003
CE01_caisse_003	Bayiga	$2a$06$g3uhh0WJoJsjFZoXhxx6..6AQCL8QP7HUwR0jL7XTFjRntm4QZmuW	caisse	1	Ramses	Bayiga	rbayi@nbfo.coop	677797754	2025-12-28 00:30:52.697812	\N	actif	\N	CAI_12-2025_003
SYS_auditeur_002	ngue	$2a$06$HyEQw0sgQ6.faprtp4h9vOFTaf1rGolJCbROL8bzmmrpCW0MP1yiG	auditeur	\N	William	Ngue	billyngue@nbfo.coop	655565758	2025-12-28 00:31:54.430333	\N	actif	\N	AUD_12-2025_002
CE01_admin_004	stock_ce01	$2a$06$SOokc4thP0Apge/MIroSs.nvgEXe6zWMFzBr5C7ZdjiT3t/5lmpVS	admin	1	William	Nguele	billynguele@nbfo.coop	699989796	2026-01-18 12:26:27.126949	\N	actif	\N	ADM_01-2026_004
\.


--
-- Data for Name: virtual_revenues; Type: TABLE DATA; Schema: public; Owner: nbfodb_user
--

COPY "public"."virtual_revenues" ("id", "lot_id", "quantite", "prix_ref", "qual", "coef_qualite", "estimee", "tax_rate", "tax_amount", "status", "created_at", "realized_at", "net_amount", "quantite_restante", "profit_unitaire_virtuel", "benefice_espere", "admission_id") FROM stdin;
2	5	100.00	500.00	1	1.0000	50000.00	0.1200	6000.00	pending	2025-12-22 11:19:01.278157+00	\N	44000.00	100.00	60.0000000000000000	6000.00	11
1	5	100.00	500.00	1	1.0000	50000.00	0.1200	6000.00	pending	2025-12-22 11:13:09.395289+00	\N	44000.00	95.00	60.0000000000000000	6000.00	10
3	9	5.00	1200.00	0	1.0000	6000.00	0.3450	2070.00	pending	2025-12-22 14:08:18.039342+00	\N	3930.00	5.00	414.0000000000000000	2070.00	12
9	13	1000.00	650.00	A	1.0000	650000.00	0.1250	81250.00	pending	2025-12-27 00:09:00.438581+00	\N	568750.00	1000.00	\N	81250.00	27
10	12	1000.00	650.00	A	1.0000	650000.00	0.1300	84500.00	pending	2025-12-27 00:14:12.036329+00	\N	565500.00	1000.00	\N	84500.00	28
11	10	500.00	2500.00	A	1.0000	1250000.00	0.1350	168750.00	pending	2025-12-27 09:13:43.681325+00	\N	1081250.00	500.00	\N	168750.00	29
12	8	345.00	2500.00	A	1.0000	862500.00	0.1250	107812.50	pending	2025-12-27 13:50:08.778313+00	\N	754687.50	345.00	\N	107812.50	30
13	14	6000.00	500.00	A	1.0000	3000000.00	0.0700	210000.00	pending	2025-12-27 13:51:01.630571+00	\N	2790000.00	6000.00	\N	210000.00	31
14	6	5000.00	5000.00	A	1.0000	25000000.00	0.0500	1250000.00	pending	2025-12-27 13:51:33.133334+00	\N	23750000.00	5000.00	\N	1250000.00	32
15	17	180.00	17850.00	A	1.0000	3213000.00	0.1300	417690.00	pending	2025-12-27 13:55:20.753279+00	\N	2795310.00	180.00	\N	417690.00	33
16	15	500.00	1400.00	A	1.0000	700000.00	0.0500	35000.00	pending	2025-12-27 13:55:48.506494+00	\N	665000.00	500.00	\N	35000.00	34
17	16	500.00	5000.00	A	1.0000	2500000.00	0.0500	125000.00	pending	2025-12-27 13:56:35.411322+00	\N	2375000.00	500.00	\N	125000.00	35
18	9	500.00	2500.00	A	1.0000	1250000.00	0.1650	206250.00	pending	2025-12-27 13:57:01.200996+00	\N	1043750.00	500.00	\N	206250.00	36
19	15	800.00	1400.00	A	1.0000	1120000.00	0.0500	56000.00	pending	2025-12-27 13:58:36.800579+00	\N	1064000.00	800.00	\N	56000.00	37
20	13	1000.00	650.00	A	1.0000	650000.00	0.1850	120250.00	pending	2025-12-27 13:59:09.789145+00	\N	529750.00	1000.00	\N	120250.00	38
21	8	500.00	2500.00	C	0.8000	1000000.00	0.1200	120000.00	pending	2025-12-28 00:18:50.288756+00	\N	880000.00	500.00	\N	120000.00	39
22	18	5000.00	4500.00	A	1.0000	22500000.00	0.0500	1125000.00	pending	2026-01-14 23:03:01.610868+00	\N	21375000.00	5000.00	\N	1125000.00	40
23	17	30.00	17850.00	C	0.8000	428400.00	0.1550	66402.00	pending	2026-01-16 16:39:55.857779+00	\N	361998.00	30.00	\N	66402.00	41
24	5	47.00	5000.00	A	1.0000	235000.00	0.0500	11750.00	pending	2026-01-18 13:27:11.838263+00	\N	223250.00	47.00	\N	11750.00	44
25	17	500.00	17850.00	A	1.0000	8925000.00	0.1550	1383375.00	pending	2026-01-21 02:19:02.690272+00	\N	7541625.00	500.00	\N	1383375.00	45
26	15	75.00	1400.00	A	1.0000	105000.00	0.0500	5250.00	pending	2026-01-23 01:18:55.687236+00	\N	99750.00	75.00	\N	5250.00	46
27	16	1200.00	5000.00	A	1.0000	6000000.00	0.0700	420000.00	pending	2026-01-24 18:20:42.203286+00	\N	5580000.00	1200.00	\N	420000.00	47
28	10	2500.00	2500.00	A	1.0000	6250000.00	0.1300	812500.00	pending	2026-01-24 18:22:31.562276+00	\N	5437500.00	2500.00	\N	812500.00	48
29	14	1000.00	500.00	A	1.0000	500000.00	0.0500	25000.00	pending	2026-01-24 18:23:16.549787+00	\N	475000.00	1000.00	\N	25000.00	49
\.


--
-- Name: admissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."admissions_id_seq"', 49, true);


--
-- Name: arrondissements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."arrondissements_id_seq"', 358, true);


--
-- Name: audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."audit_id_seq"', 1, false);


--
-- Name: caisse_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."caisse_id_seq"', 1, false);


--
-- Name: caisse_lignes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."caisse_lignes_id_seq"', 1, false);


--
-- Name: cheques_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."cheques_id_seq"', 1, false);


--
-- Name: departements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."departements_id_seq"', 58, true);


--
-- Name: employers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."employers_id_seq"', 321, true);


--
-- Name: internal_bank_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."internal_bank_logs_id_seq"', 25, true);


--
-- Name: logs_deploiement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."logs_deploiement_id_seq"', 1, false);


--
-- Name: lots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."lots_id_seq"', 18, true);


--
-- Name: lots_traces_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."lots_traces_id_seq"', 1, false);


--
-- Name: magasins_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."magasins_id_seq"', 21, true);


--
-- Name: messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."messages_id_seq"', 1, false);


--
-- Name: operations_caisse_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."operations_caisse_id_seq"', 1, false);


--
-- Name: operations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."operations_id_seq"', 1, false);


--
-- Name: producteurs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."producteurs_id_seq"', 363, true);


--
-- Name: realized_gains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."realized_gains_id_seq"', 1, false);


--
-- Name: regions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."regions_id_seq"', 10, true);


--
-- Name: retraits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."retraits_id_seq"', 34, true);


--
-- Name: transferts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."transferts_id_seq"', 1, false);


--
-- Name: transferts_urgence_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."transferts_urgence_id_seq"', 1, false);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."users_id_seq"', 138, true);


--
-- Name: virtual_revenues_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nbfodb_user
--

SELECT pg_catalog.setval('"public"."virtual_revenues_id_seq"', 29, true);


--
-- Name: admissions admissions_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_pkey" PRIMARY KEY ("id");


--
-- Name: arrondissements arrondissements_nom_departement_id_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."arrondissements"
    ADD CONSTRAINT "arrondissements_nom_departement_id_key" UNIQUE ("nom", "departement_id");


--
-- Name: arrondissements arrondissements_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."arrondissements"
    ADD CONSTRAINT "arrondissements_pkey" PRIMARY KEY ("id");


--
-- Name: audit audit_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."audit"
    ADD CONSTRAINT "audit_pkey" PRIMARY KEY ("id");


--
-- Name: caisse_lignes caisse_lignes_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse_lignes"
    ADD CONSTRAINT "caisse_lignes_pkey" PRIMARY KEY ("id");


--
-- Name: caisse caisse_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse"
    ADD CONSTRAINT "caisse_pkey" PRIMARY KEY ("id");


--
-- Name: cheques cheques_numero_cheque_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_numero_cheque_key" UNIQUE ("numero_cheque");


--
-- Name: cheques cheques_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_pkey" PRIMARY KEY ("id");


--
-- Name: departement_codes departement_codes_code_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departement_codes"
    ADD CONSTRAINT "departement_codes_code_key" UNIQUE ("code");


--
-- Name: departement_codes departement_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departement_codes"
    ADD CONSTRAINT "departement_codes_pkey" PRIMARY KEY ("departement_id");


--
-- Name: departements departements_nom_region_id_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departements"
    ADD CONSTRAINT "departements_nom_region_id_key" UNIQUE ("nom", "region_id");


--
-- Name: departements departements_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departements"
    ADD CONSTRAINT "departements_pkey" PRIMARY KEY ("id");


--
-- Name: employers employers_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."employers"
    ADD CONSTRAINT "employers_pkey" PRIMARY KEY ("id");


--
-- Name: internal_bank_logs internal_bank_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."internal_bank_logs"
    ADD CONSTRAINT "internal_bank_logs_pkey" PRIMARY KEY ("id");


--
-- Name: logs_deploiement logs_deploiement_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."logs_deploiement"
    ADD CONSTRAINT "logs_deploiement_pkey" PRIMARY KEY ("id");


--
-- Name: lots lots_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots"
    ADD CONSTRAINT "lots_pkey" PRIMARY KEY ("id");


--
-- Name: lots_traces lots_traces_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots_traces"
    ADD CONSTRAINT "lots_traces_pkey" PRIMARY KEY ("id");


--
-- Name: magasins magasins_code_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."magasins"
    ADD CONSTRAINT "magasins_code_key" UNIQUE ("code");


--
-- Name: magasins magasins_nom_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."magasins"
    ADD CONSTRAINT "magasins_nom_key" UNIQUE ("nom");


--
-- Name: magasins magasins_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."magasins"
    ADD CONSTRAINT "magasins_pkey" PRIMARY KEY ("id");


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");


--
-- Name: operations_caisse operations_caisse_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations_caisse"
    ADD CONSTRAINT "operations_caisse_pkey" PRIMARY KEY ("id");


--
-- Name: operations operations_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations"
    ADD CONSTRAINT "operations_pkey" PRIMARY KEY ("id");


--
-- Name: producteurs producteurs_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs"
    ADD CONSTRAINT "producteurs_pkey" PRIMARY KEY ("id");


--
-- Name: producteurs producteurs_tel_producteur_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs"
    ADD CONSTRAINT "producteurs_tel_producteur_key" UNIQUE ("tel_producteur");


--
-- Name: quality_coeff quality_coeff_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."quality_coeff"
    ADD CONSTRAINT "quality_coeff_pkey" PRIMARY KEY ("qual");


--
-- Name: realized_gains realized_gains_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."realized_gains"
    ADD CONSTRAINT "realized_gains_pkey" PRIMARY KEY ("id");


--
-- Name: regions regions_nom_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_nom_key" UNIQUE ("nom");


--
-- Name: regions regions_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_pkey" PRIMARY KEY ("id");


--
-- Name: retraits retraits_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "retraits_pkey" PRIMARY KEY ("id");


--
-- Name: tax_rates tax_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."tax_rates"
    ADD CONSTRAINT "tax_rates_pkey" PRIMARY KEY ("category");


--
-- Name: transferts transferts_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts"
    ADD CONSTRAINT "transferts_pkey" PRIMARY KEY ("id");


--
-- Name: transferts_urgence transferts_urgence_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts_urgence"
    ADD CONSTRAINT "transferts_urgence_pkey" PRIMARY KEY ("id");


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");


--
-- Name: virtual_revenues virtual_revenues_pkey; Type: CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."virtual_revenues"
    ADD CONSTRAINT "virtual_revenues_pkey" PRIMARY KEY ("id");


--
-- Name: idx_realized_gains_lot; Type: INDEX; Schema: public; Owner: nbfodb_user
--

CREATE INDEX "idx_realized_gains_lot" ON "public"."realized_gains" USING "btree" ("lot_id");


--
-- Name: idx_transferts_depart; Type: INDEX; Schema: public; Owner: nbfodb_user
--

CREATE INDEX "idx_transferts_depart" ON "public"."transferts" USING "btree" ("magasin_depart");


--
-- Name: idx_transferts_dest; Type: INDEX; Schema: public; Owner: nbfodb_user
--

CREATE INDEX "idx_transferts_dest" ON "public"."transferts" USING "btree" ("magasin_destination");


--
-- Name: idx_virtual_revenues_lot; Type: INDEX; Schema: public; Owner: nbfodb_user
--

CREATE INDEX "idx_virtual_revenues_lot" ON "public"."virtual_revenues" USING "btree" ("lot_id");


--
-- Name: idx_virtual_revenues_status; Type: INDEX; Schema: public; Owner: nbfodb_user
--

CREATE INDEX "idx_virtual_revenues_status" ON "public"."virtual_revenues" USING "btree" ("status");


--
-- Name: transferts_urgence trg_audit_transfert; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_audit_transfert" BEFORE UPDATE ON "public"."transferts_urgence" FOR EACH ROW EXECUTE FUNCTION "public"."fn_finaliser_transfert"();


--
-- Name: employers trg_generate_employer_id; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_generate_employer_id" BEFORE INSERT OR UPDATE ON "public"."employers" FOR EACH ROW EXECUTE FUNCTION "public"."generate_employer_id"();


--
-- Name: producteurs trg_generate_producteur_id; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_generate_producteur_id" BEFORE INSERT OR UPDATE ON "public"."producteurs" FOR EACH ROW EXECUTE FUNCTION "public"."generate_producteur_id"();


--
-- Name: users trg_generate_user_id; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_generate_user_id" BEFORE INSERT OR UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."generate_user_id"();


--
-- Name: retraits trg_handle_magasin_transfer; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_handle_magasin_transfer" AFTER INSERT ON "public"."retraits" FOR EACH ROW EXECUTE FUNCTION "public"."handle_magasin_transfer"();


--
-- Name: admissions trg_nbfo_admission_insert; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_nbfo_admission_insert" AFTER INSERT ON "public"."admissions" FOR EACH ROW EXECUTE FUNCTION "public"."nbfo_on_admission_insert"();


--
-- Name: lots trg_nbfo_lots_change; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_nbfo_lots_change" AFTER INSERT OR UPDATE ON "public"."lots" FOR EACH ROW EXECUTE FUNCTION "public"."nbfo_on_lots_change"();


--
-- Name: retraits trg_nbfo_retrait_finance; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_nbfo_retrait_finance" AFTER INSERT ON "public"."retraits" FOR EACH ROW EXECUTE FUNCTION "public"."nbfo_on_retrait_insert"();


--
-- Name: retraits trg_retraits_role; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_retraits_role" BEFORE INSERT OR UPDATE ON "public"."retraits" FOR EACH ROW EXECUTE FUNCTION "public"."check_destruction_role"();


--
-- Name: transferts_urgence trg_transfert_validation_finale; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_transfert_validation_finale" BEFORE UPDATE ON "public"."transferts_urgence" FOR EACH ROW EXECUTE FUNCTION "public"."fn_execute_transfert_valide"();


--
-- Name: retraits trg_update_stock_retrait; Type: TRIGGER; Schema: public; Owner: nbfodb_user
--

CREATE TRIGGER "trg_update_stock_retrait" BEFORE INSERT ON "public"."retraits" FOR EACH ROW EXECUTE FUNCTION "public"."update_stock_on_retrait"();


--
-- Name: admissions admissions_arrondissement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_arrondissement_id_fkey" FOREIGN KEY ("arrondissement_id") REFERENCES "public"."arrondissements"("id") ON DELETE SET NULL;


--
-- Name: admissions admissions_departement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_departement_id_fkey" FOREIGN KEY ("departement_id") REFERENCES "public"."departements"("id") ON DELETE SET NULL;


--
-- Name: admissions admissions_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE CASCADE;


--
-- Name: admissions admissions_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_magasin_id_fkey" FOREIGN KEY ("magasin_id") REFERENCES "public"."magasins"("id") ON DELETE CASCADE;


--
-- Name: admissions admissions_producteur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_producteur_id_fkey" FOREIGN KEY ("producteur_id") REFERENCES "public"."producteurs"("id") ON DELETE CASCADE;


--
-- Name: admissions admissions_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."admissions"
    ADD CONSTRAINT "admissions_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE SET NULL;


--
-- Name: arrondissements arrondissements_departement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."arrondissements"
    ADD CONSTRAINT "arrondissements_departement_id_fkey" FOREIGN KEY ("departement_id") REFERENCES "public"."departements"("id") ON DELETE CASCADE;


--
-- Name: caisse_lignes caisse_lignes_caisse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse_lignes"
    ADD CONSTRAINT "caisse_lignes_caisse_id_fkey" FOREIGN KEY ("caisse_id") REFERENCES "public"."caisse"("id") ON DELETE CASCADE;


--
-- Name: caisse_lignes caisse_lignes_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse_lignes"
    ADD CONSTRAINT "caisse_lignes_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE SET NULL;


--
-- Name: caisse_lignes caisse_lignes_producteur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."caisse_lignes"
    ADD CONSTRAINT "caisse_lignes_producteur_id_fkey" FOREIGN KEY ("producteur_id") REFERENCES "public"."producteurs"("id") ON DELETE SET NULL;


--
-- Name: departement_codes departement_codes_departement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departement_codes"
    ADD CONSTRAINT "departement_codes_departement_id_fkey" FOREIGN KEY ("departement_id") REFERENCES "public"."departements"("id");


--
-- Name: departements departements_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."departements"
    ADD CONSTRAINT "departements_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE CASCADE;


--
-- Name: employers employers_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."employers"
    ADD CONSTRAINT "employers_magasin_id_fkey" FOREIGN KEY ("magasin_id") REFERENCES "public"."magasins"("id") ON DELETE CASCADE;


--
-- Name: retraits fk_retrait_admission; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "fk_retrait_admission" FOREIGN KEY ("admission_id") REFERENCES "public"."admissions"("id");


--
-- Name: virtual_revenues fk_virtual_admission; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."virtual_revenues"
    ADD CONSTRAINT "fk_virtual_admission" FOREIGN KEY ("admission_id") REFERENCES "public"."admissions"("id") ON DELETE CASCADE;


--
-- Name: lots_traces lots_traces_admission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots_traces"
    ADD CONSTRAINT "lots_traces_admission_id_fkey" FOREIGN KEY ("admission_id") REFERENCES "public"."admissions"("id");


--
-- Name: lots_traces lots_traces_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots_traces"
    ADD CONSTRAINT "lots_traces_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id");


--
-- Name: lots_traces lots_traces_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."lots_traces"
    ADD CONSTRAINT "lots_traces_magasin_id_fkey" FOREIGN KEY ("magasin_id") REFERENCES "public"."magasins"("id");


--
-- Name: magasins magasins_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."magasins"
    ADD CONSTRAINT "magasins_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE SET NULL;


--
-- Name: operations_caisse operations_caisse_caisse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations_caisse"
    ADD CONSTRAINT "operations_caisse_caisse_id_fkey" FOREIGN KEY ("caisse_id") REFERENCES "public"."caisse"("id") ON DELETE SET NULL;


--
-- Name: operations_caisse operations_caisse_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations_caisse"
    ADD CONSTRAINT "operations_caisse_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE SET NULL;


--
-- Name: operations_caisse operations_caisse_producteur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."operations_caisse"
    ADD CONSTRAINT "operations_caisse_producteur_id_fkey" FOREIGN KEY ("producteur_id") REFERENCES "public"."producteurs"("id") ON DELETE SET NULL;


--
-- Name: producteurs producteurs_arrondissement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs"
    ADD CONSTRAINT "producteurs_arrondissement_id_fkey" FOREIGN KEY ("arrondissement_id") REFERENCES "public"."arrondissements"("id") ON DELETE SET NULL;


--
-- Name: producteurs producteurs_departement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs"
    ADD CONSTRAINT "producteurs_departement_id_fkey" FOREIGN KEY ("departement_id") REFERENCES "public"."departements"("id") ON DELETE SET NULL;


--
-- Name: producteurs producteurs_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."producteurs"
    ADD CONSTRAINT "producteurs_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE SET NULL;


--
-- Name: realized_gains realized_gains_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."realized_gains"
    ADD CONSTRAINT "realized_gains_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE SET NULL;


--
-- Name: realized_gains realized_gains_virtual_revenue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."realized_gains"
    ADD CONSTRAINT "realized_gains_virtual_revenue_id_fkey" FOREIGN KEY ("virtual_revenue_id") REFERENCES "public"."virtual_revenues"("id") ON DELETE SET NULL;


--
-- Name: retraits retraits_destination_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "retraits_destination_magasin_id_fkey" FOREIGN KEY ("destination_magasin_id") REFERENCES "public"."magasins"("id") ON DELETE SET NULL;


--
-- Name: retraits retraits_destination_producteur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "retraits_destination_producteur_id_fkey" FOREIGN KEY ("destination_producteur_id") REFERENCES "public"."producteurs"("id") ON DELETE SET NULL;


--
-- Name: retraits retraits_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "retraits_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE CASCADE;


--
-- Name: retraits retraits_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."retraits"
    ADD CONSTRAINT "retraits_magasin_id_fkey" FOREIGN KEY ("magasin_id") REFERENCES "public"."magasins"("id") ON DELETE CASCADE;


--
-- Name: transferts transferts_chauffeur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts"
    ADD CONSTRAINT "transferts_chauffeur_id_fkey" FOREIGN KEY ("chauffeur_id") REFERENCES "public"."employers"("id");


--
-- Name: transferts transferts_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts"
    ADD CONSTRAINT "transferts_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id");


--
-- Name: transferts transferts_magasin_depart_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts"
    ADD CONSTRAINT "transferts_magasin_depart_fkey" FOREIGN KEY ("magasin_depart") REFERENCES "public"."magasins"("id");


--
-- Name: transferts transferts_magasin_destination_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts"
    ADD CONSTRAINT "transferts_magasin_destination_fkey" FOREIGN KEY ("magasin_destination") REFERENCES "public"."magasins"("id");


--
-- Name: transferts_urgence transferts_urgence_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts_urgence"
    ADD CONSTRAINT "transferts_urgence_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id");


--
-- Name: transferts_urgence transferts_urgence_magasin_id_depart_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts_urgence"
    ADD CONSTRAINT "transferts_urgence_magasin_id_depart_fkey" FOREIGN KEY ("magasin_id_depart") REFERENCES "public"."magasins"("id");


--
-- Name: transferts_urgence transferts_urgence_magasin_id_dest_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."transferts_urgence"
    ADD CONSTRAINT "transferts_urgence_magasin_id_dest_fkey" FOREIGN KEY ("magasin_id_dest") REFERENCES "public"."magasins"("id");


--
-- Name: users users_magasin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_magasin_id_fkey" FOREIGN KEY ("magasin_id") REFERENCES "public"."magasins"("id") ON DELETE SET NULL;


--
-- Name: virtual_revenues virtual_revenues_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nbfodb_user
--

ALTER TABLE ONLY "public"."virtual_revenues"
    ADD CONSTRAINT "virtual_revenues_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lots"("id") ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

