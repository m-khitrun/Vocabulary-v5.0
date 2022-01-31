/**************************************************************************
* Copyright 2016 Observational Health Data Sciences and Informatics (OHDSI)
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
* 
* Authors: Christian Reich, Timur Vakhitov, Eduard Korchmar
* Date: 2021
**************************************************************************/

-- 1. Update latest_update field to new date 
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.SetLatestUpdate(
	pVocabularyName			=> 'RxNorm',
	pVocabularyDate			=> (SELECT vocabulary_date FROM sources.rxnatomarchive LIMIT 1),
	pVocabularyVersion		=> (SELECT vocabulary_version FROM sources.rxnatomarchive LIMIT 1),
	pVocabularyDevSchema	=> 'DEV_RXNORM'
);
END $_$;

-- 2. Truncate all working tables
TRUNCATE TABLE concept_stage;
TRUNCATE TABLE concept_relationship_stage;
TRUNCATE TABLE concept_synonym_stage;
TRUNCATE TABLE pack_content_stage;
TRUNCATE TABLE drug_strength_stage;

--3. Insert into concept_stage
--3.1. Create table for Precise Ingredients that must change class to Ingredients
drop table if exists pi_promotion;
create table pi_promotion as
select distinct r1.rxcui2 as component_rxcui, r1.rxcui1 as pi_rxcui, r2.rxcui1 as i_rxcui 
from sources.rxnrel r1
join sources.rxnrel r2 on
	r2.rxcui2 = r1.rxcui2 and
	r2.rela = 'has_ingredient' and
	r1.rela = 'has_precise_ingredient'
where
	--All three are active
	NOT EXISTS (
		SELECT 1
		FROM sources.rxnatomarchive arch
		WHERE arch.rxcui = r1.rxcui2
			AND sab = 'RXNORM'
			AND tty IN (
				'IN',
				'DF',
				'SCDC',
				'SCDF',
				'SCD',
				'BN',
				'SBDC',
				'SBDF',
				'SBD',
				'PIN',
				'DFG',
				'SCDG',
				'SBDG'
				)
			AND rxcui <> merged_to_rxcui
		) and
	NOT EXISTS (
		SELECT 1
		FROM sources.rxnatomarchive arch
		WHERE arch.rxcui = r1.rxcui1
			AND sab = 'RXNORM'
			AND tty IN (
				'IN',
				'DF',
				'SCDC',
				'SCDF',
				'SCD',
				'BN',
				'SBDC',
				'SBDF',
				'SBD',
				'PIN',
				'DFG',
				'SCDG',
				'SBDG'
				)
			AND rxcui <> merged_to_rxcui
		) and
	NOT EXISTS (
		SELECT 1
		FROM sources.rxnatomarchive arch
		WHERE arch.rxcui = r2.rxcui1
			AND sab = 'RXNORM'
			AND tty IN (
				'IN',
				'DF',
				'SCDC',
				'SCDF',
				'SCD',
				'BN',
				'SBDC',
				'SBDF',
				'SBD',
				'PIN',
				'DFG',
				'SCDG',
				'SBDG'
				)
			AND rxcui <> merged_to_rxcui
		)
;

--3.2. Get drugs, components, forms and ingredients
INSERT INTO concept_stage (
	concept_name,
	vocabulary_id,
	domain_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT distinct vocabulary_pack.CutConceptName(str),
	'RxNorm',
	'Drug',
	-- Use Ingredient concept class for promoting Precise Ingredients
	CASE 
		when p.pi_rxcui is not null 
		then 'Ingredient'
	ELSE
		-- use RxNorm tty as for Concept Classes
		CASE tty
			WHEN 'IN'
				THEN 'Ingredient'
			WHEN 'DF'
				THEN 'Dose Form'
			WHEN 'SCDC'
				THEN 'Clinical Drug Comp'
			WHEN 'SCDF'
				THEN 'Clinical Drug Form'
			WHEN 'SCD'
				THEN 'Clinical Drug'
			WHEN 'BN'
				THEN 'Brand Name'
			WHEN 'SBDC'
				THEN 'Branded Drug Comp'
			WHEN 'SBDF'
				THEN 'Branded Drug Form'
			WHEN 'SBD'
				THEN 'Branded Drug'
			WHEN 'PIN'
				THEN 'Precise Ingredient'
			WHEN 'DFG'
				THEN 'Dose Form Group'
			WHEN 'SCDG'
				THEN 'Clinical Dose Group'
			WHEN 'SBDG'
				THEN 'Branded Dose Group'
			END
		END,
	-- only Ingredients, drug components, drug forms, drugs and packs are standard concepts
	CASE 
		when p.pi_rxcui is not null 
		then 'S'
	ELSE
		CASE tty
			WHEN 'PIN'
				THEN NULL
			WHEN 'DFG'
				THEN 'C'
			WHEN 'SCDG'
				THEN 'C'
			WHEN 'SBDG'
				THEN 'C'
			WHEN 'DF'
				THEN NULL
			WHEN 'BN'
				THEN NULL
			ELSE 'S'
			END
		END,
	-- the code used in RxNorm
	rxcui,
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		),
	CASE 
		WHEN EXISTS (
				SELECT 1
				FROM sources.rxnatomarchive arch
				WHERE arch.rxcui = rx.rxcui
					AND sab = 'RXNORM'
					AND tty IN (
						'IN',
						'DF',
						'SCDC',
						'SCDF',
						'SCD',
						'BN',
						'SBDC',
						'SBDF',
						'SBD',
						'PIN',
						'DFG',
						'SCDG',
						'SBDG'
						)
					AND rxcui <> merged_to_rxcui
				)
			THEN (
					SELECT latest_update - 1
					FROM vocabulary
					WHERE vocabulary_id = 'RxNorm'
					)
		ELSE TO_DATE('20991231', 'yyyymmdd')
		END AS valid_end_date,
	CASE 
		WHEN EXISTS (
				SELECT 1
				FROM sources.rxnatomarchive arch
				WHERE arch.rxcui = rx.rxcui
					AND sab = 'RXNORM'
					AND tty IN (
						'IN',
						'DF',
						'SCDC',
						'SCDF',
						'SCD',
						'BN',
						'SBDC',
						'SBDF',
						'SBD',
						'PIN',
						'DFG',
						'SCDG',
						'SBDG'
						)
					AND rxcui <> merged_to_rxcui
				)
			THEN 'U'
		ELSE NULL
		END
FROM sources.rxnconso rx
left join pi_promotion p on
	p.pi_rxcui = rx.rxcui
WHERE sab = 'RXNORM'
	AND tty IN (
		'IN',
		'DF',
		'SCDC',
		'SCDF',
		'SCD',
		'BN',
		'SBDC',
		'SBDF',
		'SBD',
		'PIN',
		'DFG',
		'SCDG',
		'SBDG'
		);

-- Packs share rxcuis with Clinical Drugs and Branded Drugs, therefore use code as concept_code
INSERT INTO concept_stage (
	concept_name,
	vocabulary_id,
	domain_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT vocabulary_pack.CutConceptName(str),
	'RxNorm',
	'Drug',
	-- use RxNorm tty as for Concept Classes
	CASE tty
		WHEN 'BPCK'
			THEN 'Branded Pack'
		WHEN 'GPCK'
			THEN 'Clinical Pack'
		END,
	'S',
	-- Cannot use rxcui here
	code,
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		),
	CASE 
		WHEN EXISTS (
				SELECT 1
				FROM sources.rxnatomarchive arch
				WHERE arch.rxcui = rx.rxcui
					AND sab = 'RXNORM'
					AND tty IN (
						'IN',
						'DF',
						'SCDC',
						'SCDF',
						'SCD',
						'BN',
						'SBDC',
						'SBDF',
						'SBD',
						'PIN',
						'DFG',
						'SCDG',
						'SBDG'
						)
					AND rxcui <> merged_to_rxcui
				)
			THEN (
					SELECT latest_update - 1
					FROM vocabulary
					WHERE vocabulary_id = 'RxNorm'
					)
		ELSE TO_DATE('20991231', 'yyyymmdd')
		END AS valid_end_date,
	CASE 
		WHEN EXISTS (
				SELECT 1
				FROM sources.rxnatomarchive arch
				WHERE arch.rxcui = rx.code
					AND sab = 'RXNORM'
					AND tty IN (
						'IN',
						'DF',
						'SCDC',
						'SCDF',
						'SCD',
						'BN',
						'SBDC',
						'SBDF',
						'SBD',
						'PIN',
						'DFG',
						'SCDG',
						'SBDG'
						)
					AND rxcui <> merged_to_rxcui
				)
			THEN 'U'
		ELSE NULL
		END
FROM sources.rxnconso rx
WHERE rx.sab = 'RXNORM'
	AND rx.tty IN (
		'BPCK',
		'GPCK'
		);

-- Add MIN (Multiple Ingredients) as alive concepts [AVOF-3122]
INSERT INTO concept_stage (
	concept_name,
	vocabulary_id,
	domain_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT ON (rxcui) vocabulary_pack.CutConceptName(str) AS concept_name,
	'RxNorm' AS vocabulary_id,
	'Drug' AS domain_id,
	'Multiple Ingredients' AS concept_class_id,
	NULL AS standard_concept,
	rxcui AS concept_code,
	TO_TIMESTAMP(created_timestamp, 'mm/dd/yyyy hh:mm:ss pm')::DATE AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.rxnatomarchive
WHERE tty = 'MIN'
	AND sab = 'RXNORM'
ORDER BY rxcui,
	TO_TIMESTAMP(created_timestamp, 'mm/dd/yyyy hh:mm:ss pm');

--4. Add synonyms - for all classes except the packs (they use code as concept_code)
INSERT INTO concept_synonym_stage (
	synonym_concept_code,
	synonym_name,
	synonym_vocabulary_id,
	language_concept_id
	)
SELECT DISTINCT rxcui,
	vocabulary_pack.CutConceptSynonymName(rx.str),
	'RxNorm',
	4180186 -- English
FROM sources.rxnconso rx
JOIN concept_stage c ON c.concept_code = rx.rxcui
	AND c.concept_class_id NOT IN (
		'Clinical Pack',
		'Branded Pack'
		)
	AND c.vocabulary_id = 'RxNorm'
WHERE rx.sab = 'RXNORM'
	AND rx.tty IN (
		'IN',
		'DF',
		'SCDC',
		'SCDF',
		'SCD',
		'BN',
		'SBDC',
		'SBDF',
		'SBD',
		'PIN',
		'DFG',
		'SCDG',
		'SBDG',
		'SY'
		)
	AND c.vocabulary_id = 'RxNorm';

-- Add synonyms for packs
INSERT INTO concept_synonym_stage (
	synonym_concept_code,
	synonym_name,
	synonym_vocabulary_id,
	language_concept_id
	)
SELECT DISTINCT code,
	vocabulary_pack.CutConceptSynonymName(rx.str),
	'RxNorm',
	4180186 -- English
FROM sources.rxnconso rx
JOIN concept_stage c ON c.concept_code = rx.code
	AND c.concept_class_id IN (
		'Clinical Pack',
		'Branded Pack'
		)
	AND c.vocabulary_id = 'RxNorm'
WHERE rx.sab = 'RXNORM'
	AND rx.tty IN (
		'BPCK',
		'GPCK',
		'SY'
		);

--5. Add inner-RxNorm relationships
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT distinct rxcui2 AS concept_code_1, -- !! The RxNorm source files have the direction the opposite than OMOP
	rxcui1 AS concept_code_2,
	'RxNorm' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	case
		when p.pi_rxcui is not null
			then 'RxNorm has ing'
	else
		CASE -- 
			WHEN rela = 'has_precise_ingredient'
				THEN 'Has precise ing'
			WHEN rela = 'has_tradename'
				THEN 'Has tradename'
			WHEN rela = 'has_dose_form'
				THEN 'RxNorm has dose form'
			WHEN rela = 'has_form'
				THEN 'Has form' -- links Ingredients to Precise Ingredients
			WHEN rela = 'has_ingredient'
				THEN 'RxNorm has ing'
			WHEN rela = 'constitutes'
				THEN 'Constitutes'
			WHEN rela = 'contains'
				THEN 'Contains'
			WHEN rela = 'reformulated_to'
				THEN 'Reformulated in'
			WHEN rela = 'inverse_isa'
				THEN 'RxNorm inverse is a'
			WHEN rela = 'has_quantified_form'
				THEN 'Has quantified form' -- links extended release tablets to 12 HR extended release tablets
			WHEN rela = 'quantified_form_of'
				THEN 'Quantified form of'
			WHEN rela = 'consists_of'
				THEN 'Consists of'
			WHEN rela = 'ingredient_of'
				THEN 'RxNorm ing of'
			WHEN rela = 'precise_ingredient_of'
				THEN 'Precise ing of'
			WHEN rela = 'dose_form_of'
				THEN 'RxNorm dose form of'
			WHEN rela = 'isa'
				THEN 'RxNorm is a'
			WHEN rela = 'contained_in'
				THEN 'Contained in'
			WHEN rela = 'form_of'
				THEN 'Form of'
			WHEN rela = 'reformulation_of'
				THEN 'Reformulation of'
			WHEN rela = 'tradename_of'
				THEN 'Tradename of'
			WHEN rela = 'doseformgroup_of'
				THEN 'Dose form group of'
			WHEN rela = 'has_doseformgroup'
				THEN 'Has dose form group'
			ELSE 'non-existing'
			END 
		END AS relationship_id,
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM (
	SELECT rxcui1,
		rxcui2,
		rela
	FROM sources.rxnrel
	WHERE sab = 'RXNORM'
		AND rxcui1 IS NOT NULL
		AND rxcui2 IS NOT NULL
		AND EXISTS (
			SELECT 1
			FROM concept
			WHERE vocabulary_id = 'RxNorm'
				AND concept_code = rxcui1
			
			UNION ALL
			
			SELECT 1
			FROM concept_stage
			WHERE vocabulary_id = 'RxNorm'
				AND concept_code = rxcui1
			)
		AND EXISTS (
			SELECT 1
			FROM concept
			WHERE vocabulary_id = 'RxNorm'
				AND concept_code = rxcui2
			
			UNION ALL
			
			SELECT 1
			FROM concept_stage
			WHERE vocabulary_id = 'RxNorm'
				AND concept_code = rxcui2
			)
		--Mid-2020 release added seeminggly useless nonsensical relationships between dead and alive concepts that need additional investigation
		--[AVOF-2522]
		AND rela NOT IN (
			'has_part',
			'has_ingredients',
			'part_of',
			'ingredients_of'
			)
	) AS s0
	
--Exclude the old link to ingredient
left join pi_promotion p on
	s0.rxcui1 = p.pi_rxcui
left join pi_promotion p2 on
	s0.rxcui1 = p2.i_rxcui and
	s0.rxcui2 = p2.component_rxcui
where p2.i_rxcui is null
;
--Update link to Ingredient where relation is replaced by the precise ingredients
update concept_relationship_stage r
set
	concept_code_1 = p.pi_rxcui
from pi_promotion p
where
	r.concept_code_2 = p.component_rxcui and
	r.relationship_id = 'RxNorm ing of' and
	r.invalid_reason is null and
	r.concept_code_1 = p.i_rxcui
;
--Delete reverse link for promoted precise ingredients
delete from concept_relationship_stage r
where exists
	(
		select 1
		from pi_promotion p
		where
			r.concept_code_2 = p.component_rxcui and
			r.relationship_id = 'Precise ing of' and
			r.invalid_reason is null and
			r.concept_code_1 = p.pi_rxcui
	)
;
--check for non-existing relationships
ALTER TABLE concept_relationship_stage ADD CONSTRAINT tmp_constraint_relid FOREIGN KEY (relationship_id) REFERENCES relationship (relationship_id);
ALTER TABLE concept_relationship_stage DROP CONSTRAINT tmp_constraint_relid;

--Rename "RxNorm has ing" to "Has brand name" if concept_code_2 has the concept_class_id='Brand Name' and reverse
UPDATE concept_relationship_stage crs_m
SET RELATIONSHIP_ID = 'Has brand name'
WHERE EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		LEFT JOIN concept_stage cs ON cs.concept_code = crs.concept_code_2
			AND cs.vocabulary_id = crs.vocabulary_id_2
			AND cs.concept_class_id = 'Brand Name'
		LEFT JOIN concept c ON c.concept_code = crs.concept_code_2
			AND c.vocabulary_id = crs.vocabulary_id_2
			AND c.concept_class_id = 'Brand Name'
		WHERE crs.invalid_reason IS NULL
			AND crs.relationship_id = 'RxNorm has ing'
			AND COALESCE(cs.concept_code, c.concept_code) IS NOT NULL
			AND crs_m.concept_code_1 = crs.concept_code_1
			AND crs_m.vocabulary_id_1 = crs.vocabulary_id_1
			AND crs_m.concept_code_2 = crs.concept_code_2
			AND crs_m.vocabulary_id_2 = crs.vocabulary_id_2
			AND crs_m.relationship_id = crs.relationship_id
		);

--reverse
UPDATE concept_relationship_stage crs_m
SET RELATIONSHIP_ID = 'Brand name of'
WHERE EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		LEFT JOIN concept_stage cs ON cs.concept_code = crs.concept_code_1
			AND cs.vocabulary_id = crs.vocabulary_id_1
			AND cs.concept_class_id = 'Brand Name'
		LEFT JOIN concept c ON c.concept_code = crs.concept_code_1
			AND c.vocabulary_id = crs.vocabulary_id_1
			AND c.concept_class_id = 'Brand Name'
		WHERE crs.invalid_reason IS NULL
			AND crs.relationship_id = 'RxNorm ing of'
			AND COALESCE(cs.concept_code, c.concept_code) IS NOT NULL
			AND crs_m.concept_code_1 = crs.concept_code_1
			AND crs_m.vocabulary_id_1 = crs.vocabulary_id_1
			AND crs_m.concept_code_2 = crs.concept_code_2
			AND crs_m.vocabulary_id_2 = crs.vocabulary_id_2
			AND crs_m.relationship_id = crs.relationship_id
		);

-- Add missing relationships between Branded Packs and their Brand Names
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
WITH pb AS (
		SELECT *
		FROM (
			SELECT pack_code,
				pack_brand,
				brand_code,
				brand_name
			FROM (
				-- The brand names are either listed as tty PSN (prescribing name) or SY (synonym). If they are not listed they don't exist
				SELECT p.rxcui AS pack_code,
					coalesce(b.str, s.str) AS pack_brand
				FROM sources.rxnconso p
				LEFT JOIN sources.rxnconso b ON p.rxcui = b.rxcui
					AND b.sab = 'RXNORM'
					AND b.tty = 'PSN'
				LEFT JOIN sources.rxnconso s ON p.rxcui = s.rxcui
					AND s.sab = 'RXNORM'
					AND s.tty = 'SY'
				WHERE p.sab = 'RXNORM'
					AND p.tty = 'BPCK'
				) AS s0
			JOIN (
				SELECT concept_code AS brand_code,
					concept_name AS brand_name
				FROM concept_stage
				WHERE vocabulary_id = 'RxNorm'
					AND concept_class_id = 'Brand Name'
				) AS s1 ON REPLACE(pack_brand, '-', ' ') ILIKE '%' || REPLACE(brand_name, '-', ' ') || '%'
			) AS s2
		-- apply the slow regexp only to the ones preselected by instr
		WHERE LOWER(REPLACE(pack_brand, '-', ' ')) ~ ('(^|\s|\W)' || LOWER(REPLACE(brand_name, '-', ' ')) || '($|\s|\W)')
		)
SELECT DISTINCT pack_code AS concept_code_1,
	brand_code AS concept_code_2,
	'RxNorm' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'Has brand name' AS relationship_id,
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM pb p
-- kick out those duplicates where one is part of antoher brand name (like 'Demulen' in 'Demulen 1/50', or those that cannot be part of each other.
WHERE NOT EXISTS (
		SELECT 1
		FROM pb q
		WHERE q.brand_code != p.brand_code
			AND p.pack_code = q.pack_code
			AND (
				devv5.INSTR(q.brand_name, p.brand_name) > 0
				OR devv5.INSTR(q.brand_name, p.brand_name) = 0
				AND devv5.INSTR(p.brand_name, q.brand_name) = 0
				)
		)
	AND NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_1 = pack_code
			AND crs.concept_code_2 = brand_code
			AND crs.relationship_id = 'Has brand name'
		)
	AND NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_2 = pack_code
			AND crs.concept_code_1 = brand_code
			AND crs.relationship_id = 'Brand name of'
		);

-- Remove shortcut 'RxNorm has ing' relationship between 'Clinical Drug', 'Quant Clinical Drug', 'Clinical Pack' and 'Ingredient'
DELETE
FROM concept_relationship_stage r
WHERE EXISTS (
		SELECT 1
		FROM concept_stage d
		WHERE r.concept_code_1 = d.concept_code
			AND r.vocabulary_id_1 = d.vocabulary_id
			AND d.concept_class_id IN (
				'Clinical Drug',
				'Quant Clinical Drug',
				'Clinical Pack'
				)
		)
	AND EXISTS (
		SELECT 1
		FROM concept_stage d
		WHERE r.concept_code_2 = d.concept_code
			AND r.vocabulary_id_2 = d.vocabulary_id
			AND d.concept_class_id = 'Ingredient'
		)
	AND relationship_id = 'RxNorm has ing';

-- and same for reverse
DELETE
FROM concept_relationship_stage r
WHERE EXISTS (
		SELECT 1
		FROM concept_stage d
		WHERE r.concept_code_2 = d.concept_code
			AND r.vocabulary_id_1 = d.vocabulary_id
			AND d.concept_class_id IN (
				'Clinical Drug',
				'Quant Clinical Drug',
				'Clinical Pack'
				)
		)
	AND EXISTS (
		SELECT 1
		FROM concept_stage d
		WHERE r.concept_code_1 = d.concept_code
			AND r.vocabulary_id_2 = d.vocabulary_id
			AND d.concept_class_id = 'Ingredient'
		)
	AND relationship_id = 'RxNorm ing of';

--Rename 'Has tradename' to 'Has brand name'  where concept_id_1='Ingredient' and concept_id_2='Brand Name'
UPDATE concept_relationship_stage crs_m
SET relationship_id = 'Has brand name'
WHERE EXISTS (
		SELECT r.ctid
		FROM concept_relationship_stage r
		WHERE r.relationship_id = 'Has tradename'
			AND EXISTS (
				SELECT 1
				FROM concept_stage cs
				WHERE cs.concept_code = r.concept_code_1
					AND cs.vocabulary_id = r.vocabulary_id_1
					AND cs.concept_class_id = 'Ingredient'
				
				UNION ALL
				
				SELECT 1
				FROM concept c
				WHERE c.concept_code = r.concept_code_1
					AND c.vocabulary_id = r.vocabulary_id_1
					AND c.concept_class_id = 'Ingredient'
				)
			AND EXISTS (
				SELECT 1
				FROM concept_stage cs
				WHERE cs.concept_code = r.concept_code_2
					AND cs.vocabulary_id = r.vocabulary_id_2
					AND cs.concept_class_id = 'Brand Name'
				
				UNION ALL
				
				SELECT 1
				FROM concept c
				WHERE c.concept_code = r.concept_code_2
					AND c.vocabulary_id = r.vocabulary_id_2
					AND c.concept_class_id = 'Brand Name'
				)
			AND crs_m.concept_code_1 = r.concept_code_1
			AND crs_m.vocabulary_id_1 = r.vocabulary_id_1
			AND crs_m.concept_code_2 = r.concept_code_2
			AND crs_m.vocabulary_id_2 = r.vocabulary_id_2
			AND crs_m.relationship_id = r.relationship_id
		);

--and same for reverse
UPDATE concept_relationship_stage crs_m
SET relationship_id = 'Brand name of'
WHERE EXISTS (
		SELECT r.ctid
		FROM concept_relationship_stage r
		WHERE r.relationship_id = 'Tradename of'
			AND EXISTS (
				SELECT 1
				FROM concept_stage cs
				WHERE cs.concept_code = r.concept_code_1
					AND cs.vocabulary_id = r.vocabulary_id_1
					AND cs.concept_class_id = 'Brand Name'
				
				UNION ALL
				
				SELECT 1
				FROM concept c
				WHERE c.concept_code = r.concept_code_1
					AND c.vocabulary_id = r.vocabulary_id_1
					AND c.concept_class_id = 'Brand Name'
				)
			AND EXISTS (
				SELECT 1
				FROM concept_stage cs
				WHERE cs.concept_code = r.concept_code_2
					AND cs.vocabulary_id = r.vocabulary_id_2
					AND cs.concept_class_id = 'Ingredient'
				
				UNION ALL
				
				SELECT 1
				FROM concept c
				WHERE c.concept_code = r.concept_code_2
					AND c.vocabulary_id = r.vocabulary_id_2
					AND c.concept_class_id = 'Ingredient'
				)
			AND crs_m.concept_code_1 = r.concept_code_1
			AND crs_m.vocabulary_id_1 = r.vocabulary_id_1
			AND crs_m.concept_code_2 = r.concept_code_2
			AND crs_m.vocabulary_id_2 = r.vocabulary_id_2
			AND crs_m.relationship_id = r.relationship_id
		);
--6. Add cross-link and mapping table between SNOMED and RxNorm
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT d.concept_code AS concept_code_1,
	e.concept_code AS concept_code_2,
	'SNOMED' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'SNOMED - RxNorm eq' AS relationship_id,
	d.valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM concept d
JOIN sources.rxnconso r ON r.code = d.concept_code
	AND r.sab = 'SNOMEDCT_US'
	AND r.code != 'NOCODE'
JOIN concept e ON r.rxcui = e.concept_code
	AND e.vocabulary_id = 'RxNorm'
	AND e.invalid_reason IS NULL
WHERE d.vocabulary_id = 'SNOMED'
	AND d.invalid_reason IS NULL
-- Mapping table between SNOMED to RxNorm. SNOMED is both an intermediary between RxNorm AND DM+D, AND a source code

UNION ALL

SELECT DISTINCT d.concept_code AS concept_code_1,
	e.concept_code AS concept_code_2,
	'SNOMED' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'Maps to' AS relationship_id,
	d.valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM concept d
JOIN sources.rxnconso r ON r.code = d.concept_code
	AND r.sab = 'SNOMEDCT_US'
	AND r.code != 'NOCODE'
JOIN concept e ON r.rxcui = e.concept_code
	AND e.vocabulary_id = 'RxNorm'
	AND e.invalid_reason IS NULL
WHERE d.vocabulary_id = 'SNOMED'
	AND d.invalid_reason IS NULL
	AND d.concept_class_id NOT IN (
		'Dose Form',
		'Brand Name'
		);

--7. Add upgrade relationships (concept_code_2 shouldn't exists in rxnsat with atn = 'RXN_QUALITATIVE_DISTINCTION')
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT raa.rxcui AS concept_code_1,
	raa.merged_to_rxcui AS concept_code_2,
	'RxNorm' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'Concept replaced by' AS relationship_id,
	v.latest_update AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.rxnatomarchive raa
JOIN vocabulary v ON v.vocabulary_id = 'RxNorm' -- for getting the latest_update
LEFT JOIN sources.rxnsat rxs ON rxs.rxcui = raa.merged_to_rxcui
	AND rxs.atn = 'RXN_QUALITATIVE_DISTINCTION'
	AND rxs.sab = raa.sab
WHERE raa.sab = 'RXNORM'
	AND raa.tty IN (
		'IN',
		'DF',
		'SCDC',
		'SCDF',
		'SCD',
		'BN',
		'SBDC',
		'SBDF',
		'SBD',
		'PIN',
		'DFG',
		'SCDG',
		'SBDG'
		)
	AND raa.rxcui <> raa.merged_to_rxcui
	AND rxs.rxcui IS NULL;

--7.1. Add 'Maps to' between RXN_QUALITATIVE_DISTINCTION and fresh concepts (AVOF-457)
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT raa.merged_to_rxcui AS concept_code_1,
	crs.concept_code_2 AS concept_code_2,
	'RxNorm' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'Maps to' AS relationship_id,
	v.latest_update AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM concept_relationship_stage crs
JOIN sources.rxnatomarchive raa ON raa.sab = 'RXNORM'
	AND raa.tty IN (
		'IN',
		'DF',
		'SCDC',
		'SCDF',
		'SCD',
		'BN',
		'SBDC',
		'SBDF',
		'SBD',
		'PIN',
		'DFG',
		'SCDG',
		'SBDG'
		)
	AND raa.rxcui = crs.concept_code_1
	AND raa.merged_to_rxcui <> crs.concept_code_2
JOIN sources.rxnsat rxs ON rxs.rxcui = raa.merged_to_rxcui
	AND rxs.atn = 'RXN_QUALITATIVE_DISTINCTION'
	AND rxs.sab = raa.sab
JOIN vocabulary v ON v.vocabulary_id = 'RxNorm'
WHERE crs.relationship_id = 'Concept replaced by'
	AND crs.invalid_reason IS NULL
	AND crs.vocabulary_id_1 = 'RxNorm'
	AND crs.vocabulary_id_2 = 'RxNorm';

--7.2. Set standard_concept = NULL for all affected codes with RXN_QUALITATIVE_DISTINCTION (AVOF-457)
UPDATE concept_stage
SET standard_concept = NULL
WHERE (
		concept_code,
		vocabulary_id
		) IN (
		SELECT raa.merged_to_rxcui,
			crs.vocabulary_id_2
		FROM concept_relationship_stage crs
		JOIN sources.rxnatomarchive raa ON raa.sab = 'RXNORM'
			AND raa.tty IN (
				'IN',
				'DF',
				'SCDC',
				'SCDF',
				'SCD',
				'BN',
				'SBDC',
				'SBDF',
				'SBD',
				'PIN',
				'DFG',
				'SCDG',
				'SBDG'
				)
			AND raa.rxcui = crs.concept_code_1
			AND raa.merged_to_rxcui <> crs.concept_code_2
		JOIN sources.rxnsat rxs ON rxs.rxcui = raa.merged_to_rxcui
			AND rxs.atn = 'RXN_QUALITATIVE_DISTINCTION'
			AND rxs.sab = raa.sab
		WHERE crs.relationship_id = 'Concept replaced by'
			AND crs.invalid_reason IS NULL
			AND crs.vocabulary_id_1 = 'RxNorm'
			AND crs.vocabulary_id_2 = 'RxNorm'
		);

--7.3. Revive concepts which have status='active' in https://rxnav.nlm.nih.gov/REST/rxcuihistory/status.xml?type=active, but we have them in the concept with invalid_reason='U' (the source changed his mind)
DROP TABLE IF EXISTS wrong_replacements cascade;
CREATE UNLOGGED TABLE wrong_replacements AS

SELECT c.concept_code AS concept_code_1,
	c2.concept_code AS concept_code_2,
	cr.valid_start_date,
	cr.relationship_id
FROM apigrabber.GetRxNormByStatus('active') api --live grabbing
JOIN concept c ON c.concept_code = api.rxcode
	AND c.invalid_reason = 'U'
	AND c.vocabulary_id = 'RxNorm'
JOIN concept_relationship cr ON cr.concept_id_1 = c.concept_id
	AND cr.invalid_reason IS NULL
	AND cr.relationship_id = 'Concept replaced by'
JOIN concept c2 ON c2.concept_id = cr.concept_id_2

UNION ALL

--Same situation, the concepts are deprecated, but in the base tables we have them with 'U' [AVOF-1183]
(
	WITH rx AS (
			SELECT c.concept_code AS concept_code_1,
				c2.concept_code AS concept_code_2,
				cr.valid_start_date,
				cr.relationship_id,
				cr.concept_id_1,
				cr.concept_id_2
			FROM concept c
			JOIN concept_relationship cr ON cr.concept_id_1 = c.concept_id
				AND cr.relationship_id = 'Concept replaced by'
				AND cr.invalid_reason IS NULL
			JOIN concept c2 ON c2.concept_id = cr.concept_id_2
			LEFT JOIN concept_stage cs ON cs.concept_code = c.concept_code
			WHERE EXISTS (
					--there must be at least one record with rxcui = merged_to_rxcui...
					SELECT 1
					FROM sources.rxnatomarchive arch
					WHERE arch.rxcui = arch.merged_to_rxcui
						AND arch.rxcui = c.concept_code
						AND arch.sab = 'RXNORM'
						AND arch.tty IN (
							'IN',
							'DF',
							'SCDC',
							'SCDF',
							'SCD',
							'BN',
							'SBDC',
							'SBDF',
							'SBD',
							'PIN',
							'DFG',
							'SCDG',
							'SBDG'
							)
					)
				AND NOT EXISTS (
					--...and there should be no records rxcui <> merged_to_rxcui
					SELECT 1
					FROM sources.rxnatomarchive arch
					WHERE arch.rxcui <> arch.merged_to_rxcui
						AND arch.rxcui = c.concept_code
						AND arch.sab = 'RXNORM'
						AND arch.tty IN (
							'IN',
							'DF',
							'SCDC',
							'SCDF',
							'SCD',
							'BN',
							'SBDC',
							'SBDF',
							'SBD',
							'PIN',
							'DFG',
							'SCDG',
							'SBDG'
							)
					)
				AND c.invalid_reason = 'U'
				AND c.vocabulary_id = 'RxNorm'
				AND c2.vocabulary_id = 'RxNorm'
				AND cs.concept_code IS NULL --missing from concept_stage (rxnconso)
			)
	SELECT rx.concept_code_1,
		rx.concept_code_2,
		rx.valid_start_date,
		rx.relationship_id
	FROM rx
	
	UNION ALL
	--Kill 'Maps to' as well
	SELECT rx.concept_code_1,
		rx.concept_code_2,
		r.valid_start_date,
		r.relationship_id
	FROM rx
	JOIN concept_relationship r ON r.concept_id_1 = rx.concept_id_1
		AND r.concept_id_2 = rx.concept_id_2
		AND r.relationship_id = 'Maps to'
		AND r.invalid_reason IS NULL
	);

--7.3.1 deprecate current replacements
UPDATE concept_relationship_stage crs
SET valid_end_date = (
		SELECT latest_update - 1
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		),
	invalid_reason = 'D'
FROM wrong_replacements wr
WHERE crs.concept_code_1 = wr.concept_code_1
	AND crs.concept_code_2 = wr.concept_code_2
	AND crs.relationship_id = wr.relationship_id;

--7.3.1 insert new D-replacements
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT 
	wr.concept_code_1,
	wr.concept_code_2,
	'RxNorm',
	'RxNorm',
	wr.relationship_id,
	wr.valid_start_date,
	(
		SELECT latest_update - 1
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	'D'
FROM wrong_replacements wr
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_1 = wr.concept_code_1
			AND crs.concept_code_2 = wr.concept_code_2
			AND crs.relationship_id = wr.relationship_id
		);

DROP TABLE wrong_replacements;

--7.3.2 special fix for code=1000589 (RxNorm bug, concept is U but should be alive)
--set concept alive
INSERT INTO concept_stage (
	concept_name,
	vocabulary_id,
	domain_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT 'autologous cultured chondrocytes',
	'RxNorm',
	'Drug',
	'Ingredient',
	'S',
	'1000589',
	TO_DATE('20100905', 'yyyymmdd'),
	TO_DATE('20991231', 'yyyymmdd'),
	NULL
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_stage
		WHERE concept_code = '1000589'
		);

--kill replacement relationship
UPDATE concept_relationship_stage crs
SET valid_end_date = (
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
		),
	invalid_reason = 'D'
WHERE crs.concept_code_1 = '1000589'
	AND crs.concept_code_2 = '350141'
	AND crs.relationship_id = 'Concept replaced by';

--7.4 Delete non-existing concepts from concept_relationship_stage
DELETE
FROM concept_relationship_stage crs
WHERE (
		crs.concept_code_1,
		crs.vocabulary_id_1,
		crs.concept_code_2,
		crs.vocabulary_id_2
		) IN (
		SELECT crm.concept_code_1,
			crm.vocabulary_id_1,
			crm.concept_code_2,
			crm.vocabulary_id_2
		FROM concept_relationship_stage crm
		LEFT JOIN concept c1 ON c1.concept_code = crm.concept_code_1
			AND c1.vocabulary_id = crm.vocabulary_id_1
		LEFT JOIN concept_stage cs1 ON cs1.concept_code = crm.concept_code_1
			AND cs1.vocabulary_id = crm.vocabulary_id_1
		LEFT JOIN concept c2 ON c2.concept_code = crm.concept_code_2
			AND c2.vocabulary_id = crm.vocabulary_id_2
		LEFT JOIN concept_stage cs2 ON cs2.concept_code = crm.concept_code_2
			AND cs2.vocabulary_id = crm.vocabulary_id_2
		WHERE (
				c1.concept_code IS NULL
				AND cs1.concept_code IS NULL
				)
			OR (
				c2.concept_code IS NULL
				AND cs2.concept_code IS NULL
				)
		);

--7.5 Add 'Maps to' as part (duplicate) of the 'Form of' relationship between 'Precise Ingredient' and 'Ingredient' (AVOF-1167)
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT distinct crs.concept_code_1,
	crs.concept_code_2,
	crs.vocabulary_id_1,
	crs.vocabulary_id_2,
	'Maps to',
	crs.valid_start_date,
	crs.valid_end_date,
	NULL
FROM concept_relationship_stage crs
JOIN concept_stage c1 ON c1.concept_code = crs.concept_code_1
	AND c1.vocabulary_id = crs.vocabulary_id_1
	AND c1.concept_class_id = 'Precise Ingredient'
	AND c1.vocabulary_id = 'RxNorm'
JOIN concept_stage c2 ON c2.concept_code = crs.concept_code_2
	AND c2.vocabulary_id = crs.vocabulary_id_2
	AND c2.concept_class_id = 'Ingredient'
	AND c2.vocabulary_id = 'RxNorm'
	AND c2.standard_concept = 'S'
-- Check if the PI was promoted:
left join pi_promotion p on
	p.pi_rxcui = crs.concept_code_1 and
	p.i_rxcui = crs.concept_code_2
WHERE crs.relationship_id = 'Form of'
	AND crs.invalid_reason IS NULL
	AND p.pi_rxcui is null
	AND NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs_int
		WHERE crs_int.concept_code_1 = crs.concept_code_1
			AND crs_int.concept_code_2 = crs.concept_code_2
			AND crs_int.vocabulary_id_1 = crs.vocabulary_id_1
			AND crs_int.vocabulary_id_2 = crs.vocabulary_id_2
			AND crs_int.relationship_id = 'Maps to'
		);

--7.6 Make sure we explicitly deprecate old Precise Ingredient to Ingredient relationship, or AddFreshMapsTo grabs them from basic tables:
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
select distinct
	cpi.concept_code,
	ci.concept_code,
	cpi.vocabulary_id,
	ci.vocabulary_id,
	'Maps to',
	r.valid_start_date,
	(
		SELECT latest_update - 1
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	'D'
from concept ci
join concept_relationship r on
	ci.concept_class_id = 'Ingredient' and
	r.relationship_id = 'Maps to' and
	r.concept_id_2 = ci.concept_id and
	r.invalid_reason is NULL
join concept cpi on
	cpi.concept_class_id = 'Precise Ingredient' and
	cpi.concept_id = r.concept_id_1
join pi_promotion p on
	p.pi_rxcui = cpi.concept_code and
	p.i_rxcui  =  ci.concept_code;

--7.7 Add manual relationships
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.ProcessManualRelationships();
END $_$;

--8. Add 'Maps to' from MIN to Ingredient
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
SELECT DISTINCT cs_min.concept_code AS concept_code_1,
	CASE 
		WHEN cs.concept_class_id = 'Ingredient'
			THEN cs.concept_code
		ELSE cs1.concept_code
		END AS concept_code_2,
	'RxNorm' AS vocabulary_id_1,
	'RxNorm' AS vocabulary_id_2,
	'Maps to' AS relationship_id,
	cs_min.valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date
FROM sources.rxnrel rel
JOIN concept_stage cs_min ON cs_min.concept_code = rel.rxcui2
	AND cs_min.concept_class_id = 'Multiple Ingredients'
JOIN concept_stage cs ON cs.concept_code = rel.rxcui1
	AND cs.concept_class_id IN (
		'Precise Ingredient',
		'Ingredient'
		)
LEFT JOIN concept_relationship_stage crs ON crs.concept_code_1 = cs.concept_code
	AND crs.vocabulary_id_1 = 'RxNorm'
	AND relationship_id = 'Maps to'
	AND crs.invalid_reason IS NULL
	AND crs.concept_code_1 <> crs.concept_code_2
	AND crs.vocabulary_id_2 = 'RxNorm'
LEFT JOIN concept_stage cs1 ON cs1.concept_code = crs.concept_code_2
	AND cs1.concept_class_id = 'Ingredient'
WHERE rel.sab = 'RXNORM'
	AND rel.rela = 'has_part';

--9. Working with replacement mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.CheckReplacementMappings();
END $_$;

--10. Add mapping from deprecated to fresh concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.AddFreshMAPSTO();
END $_$;

--11. Deprecate 'Maps to' mappings to deprecated and upgraded concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeprecateWrongMAPSTO();
END $_$;

--12. Delete ambiguous 'Maps to' mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeleteAmbiguousMAPSTO();
END $_$;

--13. Create mapping to self for fresh concepts
ANALYZE concept_relationship_stage;
ANALYZE concept_stage;
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT concept_code AS concept_code_1,
	concept_code AS concept_code_2,
	c.vocabulary_id AS vocabulary_id_1,
	c.vocabulary_id AS vocabulary_id_2,
	'Maps to' AS relationship_id,
	v.latest_update AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM concept_stage c,
	vocabulary v
WHERE c.vocabulary_id = v.vocabulary_id
	AND c.standard_concept = 'S'
	AND NOT EXISTS -- only new mapping we don't already have
	(
		SELECT 1
		FROM concept_relationship_stage i
		WHERE c.concept_code = i.concept_code_1
			AND c.concept_code = i.concept_code_2
			AND c.vocabulary_id = i.vocabulary_id_1
			AND c.vocabulary_id = i.vocabulary_id_2
			AND i.relationship_id = 'Maps to'
		);
ANALYZE concept_relationship_stage;

--14. Turn "Clinical Drug" to "Quant Clinical Drug" and "Branded Drug" to "Quant Branded Drug"
UPDATE concept_stage c
SET concept_class_id = CASE 
		WHEN concept_class_id = 'Branded Drug'
			THEN 'Quant Branded Drug'
		ELSE 'Quant Clinical Drug'
		END
WHERE concept_class_id IN (
		'Branded Drug',
		'Clinical Drug'
		)
	AND EXISTS (
		SELECT 1
		FROM concept_relationship_stage r
		WHERE r.relationship_id = 'Quantified form of'
			AND r.concept_code_1 = c.concept_code
			AND r.vocabulary_id_1 = c.vocabulary_id
		);

--15. Create pack_content_stage table
INSERT INTO pack_content_stage
SELECT DISTINCT pc.pack_code AS pack_concept_code,
	'RxNorm' AS pack_vocabulary_id,
	cont.concept_code AS drug_concept_code,
	'RxNorm' AS drug_vocabulary_id,
	pc.amount::INT2, -- of drug units in the pack
	NULL::INT2 AS box_size -- number of the overall combinations units
FROM (
	SELECT pack_code,
		-- Parse the number at the beginning of each drug string as the amount
		SUBSTRING(pack_name, '^[0-9]+') AS amount,
		-- Parse the number in parentheses on the second position of the drug string as the quantity factor of a quantified drug (usually not listed in the concept table), not used right now
		TRANSLATE(SUBSTRING(pack_name, '\([0-9]+ [A-Za-z]+\)'), 'a()', 'a') AS quant,
		-- Don't parse the drug name, because it will be found through instr() with the known name of the component (see below)
		pack_name AS drug
	FROM (
		SELECT DISTINCT pack_code,
			-- This is the sequence to split the concept_name of the packs by the semicolon, which replaces the parentheses plus slash (see below)
			TRIM(UNNEST(regexp_matches(pack_name, '[^;]+', 'g'))) AS pack_name
		FROM (
			-- This takes a Pack name, replaces the sequence ') / ' with a semicolon for splitting, and removes the word Pack and everything thereafter (the brand name usually)
			SELECT rxcui AS pack_code,
				REGEXP_REPLACE(REPLACE(REPLACE(str, ') / ', ';'), '{', ''), '\) } Pack( \[.+\])?', '','g') AS pack_name
			FROM sources.rxnconso
			WHERE sab = 'RXNORM'
				AND tty LIKE '%PCK' -- Clinical (=Generic) or Branded Pack
			) AS s0
		) AS s1
	) AS pc
-- match by name with the component drug obtained through the 'Contains' relationship
JOIN (
	SELECT concept_code_1,
		concept_code_2,
		concept_code,
		concept_name
	FROM concept_relationship_stage r
	JOIN concept_stage ON concept_code = r.concept_code_2
	WHERE r.relationship_id = 'Contains'
		AND r.invalid_reason IS NULL
	) cont ON cont.concept_code_1 = pc.pack_code
	AND pc.drug LIKE '%' || cont.concept_name || '%'; -- this is where the component name is fit into the parsed drug name from the Pack string

;
--17. Create RxNorm's concept code ancestor
DROP TABLE IF EXISTS rxnorm_ancestor;
CREATE UNLOGGED TABLE rxnorm_ancestor AS (
	WITH RECURSIVE hierarchy_concepts(ancestor_concept_code, ancestor_vocabulary_id, descendant_concept_code, descendant_vocabulary_id, root_ancestor_concept_code, root_ancestor_vocabulary_id, full_path) AS (
		SELECT ancestor_concept_code,
			ancestor_vocabulary_id,
			descendant_concept_code,
			descendant_vocabulary_id,
			ancestor_concept_code AS root_ancestor_concept_code,
			ancestor_vocabulary_id AS root_ancestor_vocabulary_id,
			ARRAY [ROW (descendant_concept_code, descendant_vocabulary_id)] AS full_path
		FROM concepts
			
		UNION ALL
			
		SELECT c.ancestor_concept_code,
			c.ancestor_vocabulary_id,
			c.descendant_concept_code,
			c.descendant_vocabulary_id,
			root_ancestor_concept_code,
			root_ancestor_vocabulary_id,
			hc.full_path || ROW(c.descendant_concept_code, c.descendant_vocabulary_id) AS full_path
		FROM concepts c
		JOIN hierarchy_concepts hc ON hc.descendant_concept_code = c.ancestor_concept_code
			AND hc.descendant_vocabulary_id = c.ancestor_vocabulary_id
		WHERE ROW(c.descendant_concept_code, c.descendant_vocabulary_id) <> ALL (full_path)
		),
	concepts AS (
		SELECT distinct crs.concept_code_1 AS ancestor_concept_code,
			crs.vocabulary_id_1 AS ancestor_vocabulary_id,
			crs.concept_code_2 AS descendant_concept_code,
			crs.vocabulary_id_2 AS descendant_vocabulary_id
		FROM concept_relationship_stage crs
		JOIN relationship s ON s.relationship_id = crs.relationship_id
			AND s.defines_ancestry = 1
		JOIN concept_stage c1 ON c1.concept_code = crs.concept_code_1
			AND c1.vocabulary_id = crs.vocabulary_id_1
			AND c1.invalid_reason IS NULL
			AND c1.vocabulary_id = 'RxNorm'
		JOIN concept_stage c2 ON c2.concept_code = crs.concept_code_2
			AND c1.vocabulary_id = crs.vocabulary_id_2
			AND c2.invalid_reason IS NULL
			AND c2.vocabulary_id = 'RxNorm'
		WHERE crs.invalid_reason IS NULL
		) SELECT DISTINCT hc.root_ancestor_concept_code AS ancestor_concept_code,
	hc.root_ancestor_vocabulary_id AS ancestor_vocabulary_id,
	hc.descendant_concept_code,
	hc.descendant_vocabulary_id FROM hierarchy_concepts hc JOIN concept_stage cs1 ON cs1.concept_code = hc.root_ancestor_concept_code
	AND cs1.standard_concept IS NOT NULL JOIN concept_stage cs2 ON cs2.concept_code = hc.descendant_concept_code
	AND cs2.standard_concept IS NOT NULL

UNION ALL
		
	SELECT cs.concept_code,
	cs.vocabulary_id,
	cs.concept_code,
	cs.vocabulary_id FROM concept_stage cs WHERE cs.vocabulary_id = 'RxNorm'
	AND cs.invalid_reason IS NULL
	AND cs.standard_concept IS NOT NULL
	);
ANALYZE rxnorm_ancestor;
;

--18. Prepare list of concepts stemming from new precise ingredients and thus missing proper CDF as parent:
drop table if exists precise_affected cascade;
create table precise_affected as
select distinct
	s.concept_code as drug_concept_code,
	cdf.concept_code as outdated_form_code
from concept_stage s
join rxnorm_ancestor ca1 on	
	s.concept_code = ca1.descendant_concept_code
join concept_stage cdf on
	cdf.concept_class_id in ('Clinical Drug Form', 'Branded Drug Form') and
	cdf.concept_code = ca1.ancestor_concept_code

join rxnorm_ancestor ca2 on
	s.concept_code = ca2.descendant_concept_code
join pi_promotion p on
	p.component_rxcui = ca2.ancestor_concept_code
where
	s.concept_class_id <> 'Branded Drug Form' -- Separate case
;
-- Create sequence that starts after existing OMOPxxx-style concept codes
DO $$
DECLARE
	ex INTEGER;
BEGIN
	SELECT MAX(REPLACE(concept_code, 'OMOP','')::int4)+1 INTO ex FROM (
		SELECT concept_code FROM concept WHERE concept_code LIKE 'OMOP%'  AND concept_code NOT LIKE '% %' -- Last valid value of the OMOP123-type codes
		UNION ALL
		SELECT concept_code FROM drug_concept_stage WHERE concept_code LIKE 'OMOP%' AND concept_code NOT LIKE '% %' -- Last valid value of the OMOP123-type codes
	) AS s0;
	DROP SEQUENCE IF EXISTS omop_seq;
	EXECUTE 'CREATE SEQUENCE omop_seq INCREMENT BY 1 START WITH ' || ex || ' NO CYCLE CACHE 20';
END $$
;

--18.1 Create list of true new ingredients for these concepts:
drop table if exists cdf_portrait cascade;
create table cdf_portrait as
with raw_form as -- ONLY CDF
	(
		select distinct
			a.*,
			f.concept_code as df_concept_code,
			s.concept_code as ingredient_concept_code,
			i.pi_rxcui as replacing_ingredient_concept_code
		from precise_affected a
		join concept_stage x on
			x.concept_code = a.outdated_form_code and
			x.concept_class_id = 'Clinical Drug Form'
		--Original ingredient related to the form
		join concept_relationship_stage ri on
			ri.concept_code_1 = a.outdated_form_code and
			ri.invalid_reason is null
		join concept_stage s on
			s.concept_code = ri.concept_code_2 and
			s.concept_class_id = 'Ingredient'
		--Cross-reference PI promotion to replace old ingredients with new
		join rxnorm_ancestor ra on
			ra.descendant_concept_code = a.drug_concept_code
		left join pi_promotion i on
			i.i_rxcui = s.concept_code and
			ra.ancestor_concept_code = i.component_rxcui
		--Add Dose Form:
		join concept_relationship_stage rf on
			rf.invalid_reason is null and
			rf.concept_code_1 = a.outdated_form_code
		join concept_stage f on
			f.concept_code = rf.concept_code_2 and
			f.concept_class_id = 'Dose Form'
	),
--Remove rows where replacing ingredients dublicate
deduplicated as (
	select distinct 
		--static rows
		drug_concept_code,outdated_form_code,df_concept_code,
		first_value(coalesce(replacing_ingredient_concept_code, ingredient_concept_code)
		) over
		(
			partition by drug_concept_code,outdated_form_code,df_concept_code, ingredient_concept_code
			order by replacing_ingredient_concept_code
		) as true_ingredient_code
	from raw_form
),
--Prepare to assign OMOP codes by finding distinct CDF constructs
aggregated as (
	select
		drug_concept_code, outdated_form_code, df_concept_code, string_agg(true_ingredient_code, '/' order by true_ingredient_code) as ingredient_string
	from deduplicated
	group by drug_concept_code, outdated_form_code, df_concept_code
),
coded as (
	select df_concept_code, ingredient_string, 'OMOP' || nextval('omop_seq') as new_code
	from aggregated
	group by df_concept_code, ingredient_string
)
select a.*, new_code from aggregated a
join coded c on
	(a.df_concept_code, a.ingredient_string) = (c.df_concept_code, c.ingredient_string)
;
--18.2 Create portrait of missing BDFs
drop table if exists bdf_portrait cascade;
create table bdf_portrait as
select
	pa.drug_concept_code,
	pa.outdated_form_code,
	cp.new_code as new_cdf_code,
	cs.concept_code_2 as bn_code,
	NULL as new_code
from precise_affected pa
join concept_stage bdf on
	bdf.concept_code = pa.outdated_form_code and
	bdf.concept_class_id = 'Branded Drug Form'
join rxnorm_ancestor ra on
	ra.descendant_concept_code = pa.drug_concept_code
-- CDF are always part of the equation:
join cdf_portrait cp on
	cp.drug_concept_code = pa.drug_concept_code and
	cp.outdated_form_code = ra.ancestor_concept_code
-- Assert existence of direct link, not just shared ancestry
join concept_relationship_stage x on
	x.concept_code_1 = pa.outdated_form_code and
	x.concept_code_2 = cp.outdated_form_code
-- Get Brand Name:
join concept_relationship_stage cs on
	cs.concept_code_1 = pa.outdated_form_code and
	cs.invalid_reason is null and
	cs.relationship_id = 'Has brand name'
;
--Populate codes:
with portraits as (
	select outdated_form_code, new_cdf_code, bn_code, 'OMOP' || nextval('omop_seq') as new_code
	from bdf_portrait
	group by outdated_form_code, new_cdf_code, bn_code
)
update bdf_portrait b
set new_code = p.new_code
from portraits p
where	
	(p.outdated_form_code, p.new_cdf_code, p.bn_code) = (b.outdated_form_code, b.new_cdf_code, b.bn_code)
;
-- 18.3 Generate NEW relations for synthetic DF: to Ingredients, Forms and Brand Names
-- 18.3.1 CDF to Ingredients (reversed for FillDrugStrength)
insert into concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
with cdf_to_ingstr as
		(
			select distinct new_code, ingredient_string
			from cdf_portrait
		),
	cdf_to_ing as
		(
			select new_code, regexp_split_to_table(ingredient_string, '\/') as ing_code
			from cdf_to_ingstr
		)
select
	ing_code,
	new_code,
	'RxNorm',
	'RxNorm Extension',
	'RxNorm ing of',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from cdf_to_ing
;
-- 18.3.2 CDF to Dose Form
insert into concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
select distinct
	new_code,
	df_concept_code,
	'RxNorm Extension',
	'RxNorm',
	'RxNorm has dose form',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from cdf_portrait
;
-- 18.3.3 BDF to Brand Name
insert into concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
select distinct
	new_code,
	bn_code,
	'RxNorm Extension',
	'RxNorm',
	'Has brand name',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from bdf_portrait
;
-- 18.3.4. BDF to CDF (this direction for FillDrugStrength)
insert into concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
select distinct 
	new_code,
	new_cdf_code,
	'RxNorm Extension',
	'RxNorm Extension',
	'Tradename of',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from bdf_portrait
;
--18.3.5. Self Map:
insert into concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	vocabulary_id_1,
	vocabulary_id_2,
	relationship_id,
	valid_start_date,
	valid_end_date
	)
with self as
	(
		select distinct new_code from cdf_portrait
			union all
		select distinct new_code from bdf_portrait
	),
rel as
	(
		select 'Maps to' as relationship_id union all
		select 'Mapped from' as relationship_id
	)
select distinct 
	new_code,
	new_code,
	'RxNorm Extension',
	'RxNorm Extension',
	relationship_id,
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from self
join rel on True
;
--18.4. Replace relations for affected concepts:
create or replace view replacement as
	(
		select 
			drug_concept_code,
			outdated_form_code,
			new_code
		from cdf_portrait
			union all
		select 
			drug_concept_code,
			outdated_form_code,
			new_code
		from bdf_portrait
	)
;
--18.4.1. Downward facing:
update concept_relationship_stage r
set
	concept_code_2 = e.new_code,
	vocabulary_id_2 = 'RxNorm Extension'
from replacement e
where
	r.invalid_reason is null and
	r.concept_code_1 = e.drug_concept_code and
	r.concept_code_2 = e.outdated_form_code
;
--18.4.2. Upward facing:
update concept_relationship_stage r
set
	concept_code_1 = e.new_code,
	vocabulary_id_1 = 'RxNorm Extension'
from replacement e
where
	r.invalid_reason is null and
	r.concept_code_2 = e.drug_concept_code and
	r.concept_code_1 = e.outdated_form_code
;
--18.5. Concept stage entries
with cdf_to_ingstr as
		(
			select distinct new_code, df_concept_code, ingredient_string
			from cdf_portrait
		),
	cdf_to_ing as
		(
			select new_code, regexp_split_to_table(ingredient_string, '\/') as ing_code
			from cdf_to_ingstr
		),
	cdf_spelled_out as
		(
			select
				cti.new_code, string_agg(si.concept_name, ' / ' ORDER BY UPPER(si.concept_name) COLLATE "C") || ' ' || sf.concept_name as new_name
			from cdf_to_ing cti
			join cdf_to_ingstr c on
				cti.new_code = c.new_code
			join concept_stage si on
				cti.ing_code = si.concept_code
			join concept_stage sf on
				c.df_concept_code = sf.concept_code
			group by cti.new_code, sf.concept_name
		),
	bdf_spelled_out as
		(
			select distinct
				b.new_code,
				i.new_name || ' [' || cb.concept_name || ']' as new_name
			from cdf_spelled_out i
			join bdf_portrait b on
				i.new_code = b.new_cdf_code
			join concept_stage cb on 
				cb.concept_code = b.bn_code
		)
insert into concept_stage (concept_code, concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept, valid_start_date, valid_end_date)
select
	new_code,
	trim(left(new_name, 255)) as concept_name,
	'Drug',
	'RxNorm Extension',
	'Clinical Drug Form',
	'S',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from cdf_spelled_out

	union all

select
	new_code,
	trim(left(new_name, 255)) as concept_name,
	'Drug',
	'RxNorm Extension',
	'Branded Drug Form',
	'S',
	(
		SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'RxNorm'
	),
	to_date('20991231','yyyymmdd')
from bdf_spelled_out
;
drop table if exists rxnorm_ancestor
;
--19. Run FillDrugStrengthStage
DO $_$
BEGIN
	PERFORM dev_rxnorm.FillDrugStrengthStage();
END $_$;

--20. Run QA-script (you can always re-run this QA manually: SELECT * FROM get_qa_rxnorm() ORDER BY info_level, description;)
DO $_$
BEGIN
	IF CURRENT_SCHEMA = 'dev_rxnorm' /*run only if we are inside dev_rxnorm*/ THEN
		ANALYZE concept_stage;
		ANALYZE concept_relationship_stage;
		ANALYZE drug_strength_stage;
		TRUNCATE TABLE rxn_info_sheet;
		INSERT INTO rxn_info_sheet SELECT * FROM dev_rxnorm.get_qa_rxnorm();
	END IF;
END $_$;

--21. Cleanup:
drop view if exists replacement;
drop table if exists precise_affected cascade;
drop table if exists cdf_portrait cascade;
drop table if exists bdf_portrait cascade;
;

--22. We need to run generic_update before small RxE clean up
DO $_$
BEGIN
	PERFORM devv5.GenericUpdate();
END $_$;

--19. Run RxE clean up
DO $_$
BEGIN
	PERFORM vocabulary_pack.RxECleanUP();
END $_$;

-- At the end, the three tables concept_stage, concept_relationship_stage and concept_synonym_stage should be ready to be fed into the generic_update.sql script