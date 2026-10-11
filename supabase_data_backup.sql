SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict tCz5WOU0mcOqu2sD7bUcyy9Tl9HZuLdFbr7RVIz6KAANIjalMbl30tCxOYhJp2H

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

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
-- Data for Name: audit_log_entries; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."audit_log_entries" ("instance_id", "id", "payload", "created_at", "ip_address") FROM stdin;
\.


--
-- Data for Name: custom_oauth_providers; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."custom_oauth_providers" ("id", "provider_type", "identifier", "name", "client_id", "client_secret", "acceptable_client_ids", "scopes", "pkce_enabled", "attribute_mapping", "authorization_params", "enabled", "email_optional", "issuer", "discovery_url", "skip_nonce_check", "cached_discovery", "discovery_cached_at", "authorization_url", "token_url", "userinfo_url", "jwks_uri", "created_at", "updated_at", "custom_claims_allowlist") FROM stdin;
\.


--
-- Data for Name: flow_state; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."flow_state" ("id", "user_id", "auth_code", "code_challenge_method", "code_challenge", "provider_type", "provider_access_token", "provider_refresh_token", "created_at", "updated_at", "authentication_method", "auth_code_issued_at", "invite_token", "referrer", "oauth_client_state_id", "linking_target_id", "email_optional") FROM stdin;
d52082eb-f986-4559-b6db-b3079155894c	669cfc05-4701-4332-b604-71cdc2a56679	183d22cc-4140-43bc-97a8-d8f40118e9a9	s256	jrXPkiNAA3dBZq-2lw3K8tRtGTQ9extSMPA6_1hRmUg	email			2026-03-18 10:45:15.677565+00	2026-03-18 10:48:42.142424+00	email/signup	2026-03-18 10:48:42.142375+00	\N	\N	\N	\N	f
99e23d62-98d0-4b10-9a30-6cfdc3b01e13	681eee4f-a7b6-46ab-87de-6965c92c5711	495939a6-f620-49eb-8b1a-196ca4038121	s256	JAbO5ZpXyhggd58XgUFHJQ2nrGM6ZWPwRQxtqXwS7ug	recovery			2026-05-23 06:28:58.204945+00	2026-05-23 06:29:10.381635+00	recovery	2026-05-23 06:29:10.381574+00	\N	\N	\N	\N	f
c2b020a7-fcd1-46ed-9bfd-42ea9e5ffd42	681eee4f-a7b6-46ab-87de-6965c92c5711	78fe6ba0-441f-484e-b728-a73144130913	s256	sao0Op3RdyKBkfRPd3VEVV4ULwSHgANt7TjMiwZTEoo	recovery			2026-09-14 13:06:36.82154+00	2026-09-14 13:06:48.05704+00	recovery	2026-09-14 13:06:48.056988+00	\N	\N	\N	\N	f
d35328c2-6082-4155-a385-96049d785a2d	681eee4f-a7b6-46ab-87de-6965c92c5711	9d367a9e-5f3b-441f-81c7-8a67d1ee8ed6	s256	5Y8dlgzvduZxdPTDcAOqklSaZhtfA8Eob5WL0A4bOTU	recovery			2026-09-23 12:23:48.865261+00	2026-09-23 12:24:01.72046+00	recovery	2026-09-23 12:24:01.720378+00	\N	\N	\N	\N	f
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at", "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token", "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at", "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin", "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change", "phone_change_token", "phone_change_sent_at", "email_change_token_current", "email_change_confirm_status", "banned_until", "reauthentication_token", "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous") FROM stdin;
00000000-0000-0000-0000-000000000000	64f965d6-d068-427d-9895-99944b60c47e	authenticated	authenticated	rlwater.cantilan@erefill.local	$2a$06$/sqvVscpVVEZmApEH8WUlO1ZmZlqZP7dlwKzQ5pPhePHjmILnPk.S	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Cantilan", "username": "rlwater_cantilan", "full_name": "RL Water Refilling Station", "station_name": "RL Water Refilling Station"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	669cfc05-4701-4332-b604-71cdc2a56679	authenticated	authenticated	aspillagalibrado@gmail.com	$2a$10$IBv.pFs3Pvc31CykZru3VekB8gNJzwUHD1g6Neoc3a77If.WU8QAO	2026-03-18 10:48:42.128352+00	\N		2026-03-18 10:45:15.683143+00	c63be2fb016b7e48fc88241d69e2bf3aba5429a1005cea9575d6a7be	2026-03-28 06:32:19.947525+00			\N	2026-10-09 00:47:44.194342+00	{"provider": "email", "providers": ["email"]}	{"sub": "669cfc05-4701-4332-b604-71cdc2a56679", "role": "owner", "town": "Cantilan", "email": "aspillagalibrado@gmail.com", "username": "librado", "full_name": "", "station_name": "Aspillaga Water Refilling Station", "email_verified": true, "phone_verified": false, "complete_address": "Purok 11, Parang Cantilan, Surigao Del Sur"}	\N	2026-03-18 10:45:15.644863+00	2026-10-09 00:47:44.24631+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	e25aa023-db2e-4e3c-9003-3a8f30b8fea3	authenticated	authenticated	waterkaw.cantilan@erefill.local	$2a$06$gMXEtjgtHYteae0bhdOwnuNJScUgn4/YQn2sNLe1F/Ukh6wQAPAUi	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Cantilan", "username": "waterkaw_cantilan", "full_name": "WATER Kaw! Purified water & Refilling Station", "station_name": "WATER Kaw! Purified water & Refilling Station"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	876fdc46-ea42-4cf2-b2bc-0c4a54a99a52	authenticated	authenticated	perch.cantilan@erefill.local	$2a$06$SFbloJ1/utsUF96UGhdZ1uhYyhYWJVWVAe9G78NH5dFnYgMOObKBq	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Cantilan", "username": "perch_cantilan", "full_name": "PERCH Water Refilling Station", "station_name": "PERCH Water Refilling Station"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	authenticated	authenticated	molejon.cantilan@erefill.local	$2a$06$WVzok.QvdJafPs3FjAg9VOmRklaJMEK2KMLxC2Uk3PMQVAWWVnqqC	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Cantilan", "username": "molejon_cantilan", "full_name": "L. Molejon Water Refilling Station", "station_name": "L. Molejon Water Refilling Station"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	df9c89ce-4e04-4dee-934c-4eb043688b20	authenticated	authenticated	mwd.madrid@erefill.local	$2a$06$fGcsxy6DVlyUYIiGraEmaOizceYxOSQcmqDbDdMdOmpd8S..9Xj5S	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Madrid", "username": "mwd_madrid", "full_name": "Madrid Water District", "station_name": "Madrid Water District (Public Utility)"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	2ebdbe41-6685-417a-8843-915117ed6e5d	authenticated	authenticated	orothel.cantilan@erefill.local	$2a$06$Xb9FWWH5ixu9IRbvV/A2eeSF0/1IvYjth8/NURV8R1whxTMZHEcV6	2026-03-19 01:43:52.841646+00	\N		2026-03-19 01:43:52.841646+00		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"role": "owner", "town": "Cantilan", "username": "orothel_cantilan", "full_name": "Orothel Water Refilling Station", "station_name": "Orothel Water Refilling Station"}	\N	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	c341c225-308e-4ff6-84bb-0f1e8732e3b8	authenticated	authenticated	jv@gmail.com	$2a$10$MNTIl3/ZmGtHyloLyABma.890e4feo5odObPcNRIsP2CFthaam0AK	2026-03-29 02:52:33.944179+00	\N		\N		\N			\N	2026-03-29 12:10:12.210897+00	{"provider": "email", "providers": ["email"]}	{"mi": "G", "sub": "c341c225-308e-4ff6-84bb-0f1e8732e3b8", "role": "owner", "town": "Cantilan", "email": "jv@gmail.com", "suffix": "", "barangay": "Parang", "latitude": 9.28104811663031, "username": "jvaspillaga", "full_name": "jv G Aspillaga ", "last_name": "Aspillaga", "longitude": 125.94190739386191, "first_name": "jv", "station_name": "Tubigan Ni Jv", "email_verified": true, "phone_verified": false, "complete_address": "Minipark, Parang, Cantilan, Surigao, Del Sur", "primary_water_type": "Purified Water"}	\N	2026-03-29 02:52:33.88663+00	2026-03-29 12:10:12.229377+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	db5ff071-d21c-406a-9759-3f1c2a39903c	authenticated	authenticated	jaylord@gmail.com	$2a$10$TDso87heF/xDoy033/USqOQOMeOeoDW2QtPpfbTkcGM6GjQGIpJaS	2026-03-23 06:47:39.286812+00	\N		\N		\N			\N	2026-10-09 01:02:26.725486+00	{"provider": "email", "providers": ["email"]}	{"sub": "db5ff071-d21c-406a-9759-3f1c2a39903c", "role": "rider", "email": "jaylord@gmail.com", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679", "username": "jaylord", "full_name": "Jaylord Buiza", "email_verified": true, "phone_verified": false}	\N	2026-03-23 06:47:39.241874+00	2026-10-09 01:02:26.782621+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	authenticated	authenticated	saysay@gmail.com	$2a$10$9sOjFsnv3eYk8ep0AJazoOzgdo2REVoulO5rEub2otmZmHD9eGpha	2026-03-29 02:57:44.315529+00	\N		\N		\N			\N	2026-03-29 02:57:44.330596+00	{"provider": "email", "providers": ["email"]}	{"sub": "aece23c3-1302-431d-aeea-a6b7fe0bd9a0", "role": "rider", "email": "saysay@gmail.com", "owner_id": "c341c225-308e-4ff6-84bb-0f1e8732e3b8", "username": "saysay", "full_name": "saysay", "email_verified": true, "phone_verified": false}	\N	2026-03-29 02:57:44.255097+00	2026-03-29 02:57:44.35078+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	de2219e9-6e80-4b21-a104-b63ae14ad08d	authenticated	authenticated	jovert@gmail.com	$2a$10$yvu5SVGKOE/r6wdkSv/8eOYk/DozRsAYf5f7ZveAtCRR8npQI4y8u	2026-03-21 02:42:11.391585+00	\N		\N		\N			\N	2026-05-31 03:00:12.698109+00	{"provider": "email", "providers": ["email"]}	{"sub": "de2219e9-6e80-4b21-a104-b63ae14ad08d", "role": "rider", "email": "jovert@gmail.com", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679", "username": "jovert", "full_name": "Jovert Ropol", "email_verified": true, "phone_verified": false}	\N	2026-03-21 02:42:11.353069+00	2026-05-31 03:00:12.718396+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	735ae478-e7bf-4db8-b184-bd84a902e870	authenticated	authenticated	admin@gmail.com	$2a$06$G43GaLyuvX/sIejvBN66d.9wi.JT2SH8xbXQqQgYM33sgdTRTc9ci	2026-05-29 10:29:48.766672+00	\N		2026-05-29 10:29:48.766672+00		\N			\N	2026-09-28 06:03:29.671199+00	{"provider": "email", "providers": ["email"]}	{"role": "admin", "username": "platform_admin", "full_name": "Platform Admin"}	\N	2026-05-29 10:29:48.766672+00	2026-10-09 00:50:30.672689+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	681eee4f-a7b6-46ab-87de-6965c92c5711	authenticated	authenticated	jheraldkima@gmail.com	\N	2026-03-29 09:21:40.599241+00	\N		\N		2026-09-23 12:23:48.912139+00			\N	2026-10-09 01:03:59.173636+00	{"provider": "google", "providers": ["google"]}	{"iss": "https://accounts.google.com", "sub": "111435439640086944817", "name": "Jherald Kim Aspillaga", "email": "jheraldkima@gmail.com", "picture": "https://lh3.googleusercontent.com/a/ACg8ocK4uh1vuJBEK7x31fyuu64ObwMwXe1V3CmlTU-ty5BZYYk6cyiH=s96-c", "full_name": "Jherald Kim Aspillaga", "avatar_url": "https://lh3.googleusercontent.com/a/ACg8ocK4uh1vuJBEK7x31fyuu64ObwMwXe1V3CmlTU-ty5BZYYk6cyiH=s96-c", "provider_id": "111435439640086944817", "email_verified": true, "phone_verified": false}	\N	2026-03-29 09:21:40.513934+00	2026-10-09 04:21:04.529661+00	\N	\N			\N		0	\N		\N	f	\N	f
\.


--
-- Data for Name: identities; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at", "updated_at", "id") FROM stdin;
669cfc05-4701-4332-b604-71cdc2a56679	669cfc05-4701-4332-b604-71cdc2a56679	{"sub": "669cfc05-4701-4332-b604-71cdc2a56679", "role": "owner", "town": "Cantilan", "email": "aspillagalibrado@gmail.com", "username": "librado", "full_name": "", "station_name": "Aspillaga Water Refilling Station", "email_verified": true, "phone_verified": false, "complete_address": "Purok 11, Parang Cantilan, Surigao Del Sur"}	email	2026-03-18 10:45:15.668486+00	2026-03-18 10:45:15.668535+00	2026-03-18 10:45:15.668535+00	53c21687-e374-4d53-be64-0c227cbdff8e
e25aa023-db2e-4e3c-9003-3a8f30b8fea3	e25aa023-db2e-4e3c-9003-3a8f30b8fea3	{"sub": "e25aa023-db2e-4e3c-9003-3a8f30b8fea3", "email": "waterkaw.cantilan@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	9e107987-a2a6-416d-be1d-8464a99dfe5a
876fdc46-ea42-4cf2-b2bc-0c4a54a99a52	876fdc46-ea42-4cf2-b2bc-0c4a54a99a52	{"sub": "876fdc46-ea42-4cf2-b2bc-0c4a54a99a52", "email": "perch.cantilan@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	43b34220-c5e4-47da-949f-f7d1a2cd0b45
4fb7557c-826c-4d67-a4ff-1f5bef0189ce	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	{"sub": "4fb7557c-826c-4d67-a4ff-1f5bef0189ce", "email": "molejon.cantilan@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	96b3fc20-a62c-4684-8446-16de3414500b
2ebdbe41-6685-417a-8843-915117ed6e5d	2ebdbe41-6685-417a-8843-915117ed6e5d	{"sub": "2ebdbe41-6685-417a-8843-915117ed6e5d", "email": "orothel.cantilan@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	384b450b-500c-4ede-bd68-ea62b07ca1e5
64f965d6-d068-427d-9895-99944b60c47e	64f965d6-d068-427d-9895-99944b60c47e	{"sub": "64f965d6-d068-427d-9895-99944b60c47e", "email": "rlwater.cantilan@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	889de1b2-bca0-418e-b74a-9bfb30c8f1dd
df9c89ce-4e04-4dee-934c-4eb043688b20	df9c89ce-4e04-4dee-934c-4eb043688b20	{"sub": "df9c89ce-4e04-4dee-934c-4eb043688b20", "email": "mwd.madrid@erefill.local"}	email	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	2026-03-19 01:43:52.841646+00	8ab1f393-24be-4416-8c00-e22684bd2f47
de2219e9-6e80-4b21-a104-b63ae14ad08d	de2219e9-6e80-4b21-a104-b63ae14ad08d	{"sub": "de2219e9-6e80-4b21-a104-b63ae14ad08d", "role": "rider", "email": "jovert@gmail.com", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679", "username": "jovert", "full_name": "Jovert Ropol", "email_verified": false, "phone_verified": false}	email	2026-03-21 02:42:11.384272+00	2026-03-21 02:42:11.384329+00	2026-03-21 02:42:11.384329+00	52217123-20c2-4f10-9733-b1fd0ac4b586
db5ff071-d21c-406a-9759-3f1c2a39903c	db5ff071-d21c-406a-9759-3f1c2a39903c	{"sub": "db5ff071-d21c-406a-9759-3f1c2a39903c", "role": "rider", "email": "jaylord@gmail.com", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679", "username": "jaylord", "full_name": "Jaylord Buiza", "email_verified": false, "phone_verified": false}	email	2026-03-23 06:47:39.280282+00	2026-03-23 06:47:39.280836+00	2026-03-23 06:47:39.280836+00	4d5236a9-65ca-466f-8364-6873d069d15b
c341c225-308e-4ff6-84bb-0f1e8732e3b8	c341c225-308e-4ff6-84bb-0f1e8732e3b8	{"mi": "G", "sub": "c341c225-308e-4ff6-84bb-0f1e8732e3b8", "role": "owner", "town": "Cantilan", "email": "jv@gmail.com", "suffix": "", "barangay": "Parang", "latitude": 9.28104811663031, "username": "jvaspillaga", "full_name": "jv G Aspillaga ", "last_name": "Aspillaga", "longitude": 125.94190739386191, "first_name": "jv", "station_name": "Tubigan Ni Jv", "email_verified": false, "phone_verified": false, "complete_address": "Minipark, Parang, Cantilan, Surigao, Del Sur", "primary_water_type": "Purified Water"}	email	2026-03-29 02:52:33.937059+00	2026-03-29 02:52:33.937107+00	2026-03-29 02:52:33.937107+00	79e868fa-e258-4fed-9fe4-5052560866d3
aece23c3-1302-431d-aeea-a6b7fe0bd9a0	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	{"sub": "aece23c3-1302-431d-aeea-a6b7fe0bd9a0", "role": "rider", "email": "saysay@gmail.com", "owner_id": "c341c225-308e-4ff6-84bb-0f1e8732e3b8", "username": "saysay", "full_name": "saysay", "email_verified": false, "phone_verified": false}	email	2026-03-29 02:57:44.307796+00	2026-03-29 02:57:44.307846+00	2026-03-29 02:57:44.307846+00	f0d9ad22-92b8-4bf3-8403-ae23df335329
735ae478-e7bf-4db8-b184-bd84a902e870	735ae478-e7bf-4db8-b184-bd84a902e870	{"sub": "735ae478-e7bf-4db8-b184-bd84a902e870", "email": "admin@gmail.com"}	email	2026-05-29 10:29:48.766672+00	2026-05-29 10:29:48.766672+00	2026-05-29 10:29:48.766672+00	2130942e-b1df-4942-baf5-40f44a23b213
111435439640086944817	681eee4f-a7b6-46ab-87de-6965c92c5711	{"iss": "https://accounts.google.com", "sub": "111435439640086944817", "name": "Jherald Kim Aspillaga", "email": "jheraldkima@gmail.com", "picture": "https://lh3.googleusercontent.com/a/ACg8ocK4uh1vuJBEK7x31fyuu64ObwMwXe1V3CmlTU-ty5BZYYk6cyiH=s96-c", "full_name": "Jherald Kim Aspillaga", "avatar_url": "https://lh3.googleusercontent.com/a/ACg8ocK4uh1vuJBEK7x31fyuu64ObwMwXe1V3CmlTU-ty5BZYYk6cyiH=s96-c", "provider_id": "111435439640086944817", "email_verified": true, "phone_verified": false}	google	2026-03-29 09:21:40.580637+00	2026-03-29 09:21:40.580688+00	2026-10-09 01:03:59.162539+00	28257229-a843-4184-8ce7-3bef28a37cb5
\.


--
-- Data for Name: instances; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."instances" ("id", "uuid", "raw_base_config", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: oauth_clients; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."oauth_clients" ("id", "client_secret_hash", "registration_type", "redirect_uris", "grant_types", "client_name", "client_uri", "logo_uri", "created_at", "updated_at", "deleted_at", "client_type", "token_endpoint_auth_method") FROM stdin;
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."sessions" ("id", "user_id", "created_at", "updated_at", "factor_id", "aal", "not_after", "refreshed_at", "user_agent", "ip", "tag", "oauth_client_id", "refresh_token_hmac_key", "refresh_token_counter", "scopes") FROM stdin;
b30a75a6-0f84-4f46-b942-267159c5899f	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-18 10:48:49.973485+00	2026-03-18 10:48:49.973485+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.5	\N	\N	\N	\N	\N
fbbcb14c-f6f3-43e7-9260-8704c331d6a2	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-03 08:05:39.10325+00	2026-10-03 08:05:39.10325+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	36.255.60.189	\N	\N	\N	\N	\N
f934df4d-ebb8-4db0-847c-a5e66dcc603b	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-03 08:05:39.550328+00	2026-10-03 08:05:39.550328+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	36.255.60.189	\N	\N	\N	\N	\N
1cd41f02-e4d4-4b19-946e-b251e17c578f	c341c225-308e-4ff6-84bb-0f1e8732e3b8	2026-03-29 12:10:12.211472+00	2026-03-29 12:10:12.211472+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
6eaa5527-1200-4391-99c1-64174d1a61c9	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-09 01:03:59.174083+00	2026-10-09 04:21:04.539321+00	\N	aal1	\N	2026-10-09 04:21:04.539229	Dart/3.13 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
da5b26b5-1aac-4cd4-8859-6e1f6ceebb4f	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-29 14:19:47.18597+00	2026-03-29 14:19:47.18597+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.185	\N	\N	\N	\N	\N
2e3eb910-22db-4932-a56f-21b648f2d33c	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-18 12:55:14.407907+00	2026-03-18 12:55:14.407907+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.3	\N	\N	\N	\N	\N
c1426e72-cf1f-477d-8eb1-5a06c7a62e15	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-19 14:50:36.801978+00	2026-03-20 12:52:52.33205+00	\N	aal1	\N	2026-03-20 12:52:52.331959	Dart/3.11 (dart:io)	112.198.31.5	\N	\N	\N	\N	\N
1370dcea-3aea-4647-9757-3cd07eab70b9	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-05-28 01:23:21.669016+00	2026-05-28 01:23:21.669016+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	175.176.85.158	\N	\N	\N	\N	\N
a6ce61e0-dc1c-4228-aacf-44715671feca	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-06 03:25:42.834457+00	2026-10-06 03:25:42.834457+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	103.180.201.129	\N	\N	\N	\N	\N
5b4f0401-6daf-4b84-9dd4-46d56b17a1b6	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-29 05:06:55.747052+00	2026-03-29 05:06:55.747052+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
a1693680-290a-480c-98c5-e1d1216212e0	669cfc05-4701-4332-b604-71cdc2a56679	2026-04-09 03:29:19.82302+00	2026-04-09 03:29:19.82302+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.169.28	\N	\N	\N	\N	\N
b8b7dbf9-0d0c-40c5-9008-84bd59787c03	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-20 23:49:16.465105+00	2026-03-21 00:48:42.214957+00	\N	aal1	\N	2026-03-21 00:48:42.214859	Dart/3.11 (dart:io)	112.198.31.1	\N	\N	\N	\N	\N
526288d2-9a68-49a8-9d0b-b7438fe802fc	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-21 01:54:30.270071+00	2026-03-21 01:54:30.270071+00	\N	aal1	\N	\N	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36	14.102.169.29	\N	\N	\N	\N	\N
7c0dd94d-0084-4b70-8a33-f76369376fd1	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-21 02:20:47.750803+00	2026-03-21 02:20:47.750803+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.1	\N	\N	\N	\N	\N
351f45dd-44f6-4d95-a6a2-b3d858d8c03c	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-05-28 06:40:04.510103+00	2026-05-28 06:40:04.510103+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	180.190.47.104	\N	\N	\N	\N	\N
115c1937-ca8a-42d3-8585-b2656a772988	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-21 02:38:15.82584+00	2026-03-21 02:38:15.82584+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.1	\N	\N	\N	\N	\N
6ec961e1-e272-4618-b5d2-e300f2146f37	de2219e9-6e80-4b21-a104-b63ae14ad08d	2026-03-21 02:42:36.487681+00	2026-03-21 02:42:36.487681+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.1	\N	\N	\N	\N	\N
98b85443-c686-479e-8c15-673e79647568	735ae478-e7bf-4db8-b184-bd84a902e870	2026-05-29 10:31:15.298228+00	2026-05-29 10:31:15.298228+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	36.255.60.187	\N	\N	\N	\N	\N
ff39d202-045f-4a32-b735-629f2fd3d8e1	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-21 03:29:20.807576+00	2026-03-22 12:11:45.404098+00	\N	aal1	\N	2026-03-22 12:11:45.403994	Dart/3.11 (dart:io)	14.102.169.28	\N	\N	\N	\N	\N
39b284ee-6d69-46f4-996b-ab69ca57ccea	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-23 07:05:22.599483+00	2026-03-23 07:05:22.599483+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.169.30	\N	\N	\N	\N	\N
06d81f00-f3d6-4d77-9879-279daa3539c5	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	2026-03-29 02:57:44.331148+00	2026-03-29 02:57:44.331148+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
ac33ad91-32c4-45c0-988b-b793eabcd5f4	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-29 04:18:25.379212+00	2026-03-29 04:18:25.379212+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
fdaa3282-22bb-45fd-a120-147598aff6c3	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-23 05:05:59.895229+00	2026-03-23 05:05:59.895229+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.169.28	\N	\N	\N	\N	\N
02fdb0c2-e4d8-4664-8709-89eb19d4e940	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-23 06:30:32.569545+00	2026-03-23 06:30:32.569545+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.169.30	\N	\N	\N	\N	\N
2c40b624-9f12-4a7e-8ed7-55c9420f6662	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-23 06:45:37.57735+00	2026-03-23 06:45:37.57735+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.169.29	\N	\N	\N	\N	\N
2ccd86bf-0b92-4cec-99ad-f86327c68f0a	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-07 03:16:15.564695+00	2026-10-07 04:37:57.664624+00	\N	aal1	\N	2026-10-07 04:37:57.664519	Dart/3.13 (dart:io)	49.149.69.93	\N	\N	\N	\N	\N
fe2c42e3-d2ac-4290-ace0-381f10788581	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-05-23 06:16:19.543894+00	2026-05-23 06:16:19.543894+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
3627b4c7-2756-4794-a38e-56b6ada4fb8e	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-03-29 09:21:40.611578+00	2026-03-29 09:21:40.611578+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
5e4ad18e-4e90-4529-be2a-d5250a9dd5dc	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-07 04:41:51.096409+00	2026-10-07 04:41:51.096409+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	49.149.69.93	\N	\N	\N	\N	\N
1a92c02d-dfab-4904-92da-04983239df40	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-03-29 09:33:33.300566+00	2026-03-29 09:33:33.300566+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.186	\N	\N	\N	\N	\N
cbd8c6f5-8dba-4ea5-a529-451526315dc6	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-07 02:20:17.148832+00	2026-10-07 04:45:07.238977+00	\N	aal1	\N	2026-10-07 04:45:07.236374	Dart/3.13 (dart:io)	49.149.69.93	\N	\N	\N	\N	\N
52b658bf-4e7a-4ab6-8678-3f2793bf974f	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-23 13:40:02.590786+00	2026-03-23 13:40:02.590786+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	112.198.31.2	\N	\N	\N	\N	\N
887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8	669cfc05-4701-4332-b604-71cdc2a56679	2026-05-31 03:27:27.740393+00	2026-05-31 08:24:32.140285+00	\N	aal1	\N	2026-05-31 08:24:32.139679	Dart/3.11 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
5f2a5288-26b8-4066-9260-b519828a3afc	669cfc05-4701-4332-b604-71cdc2a56679	2026-09-24 07:59:15.207636+00	2026-09-24 07:59:15.207636+00	\N	aal1	\N	\N	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 Edg/153.0.0.0	36.255.60.190	\N	\N	\N	\N	\N
5b4bac23-b1ba-48da-b626-8e67991a9520	735ae478-e7bf-4db8-b184-bd84a902e870	2026-05-29 11:24:39.12674+00	2026-05-31 09:44:15.586557+00	\N	aal1	\N	2026-05-31 09:44:15.58646	Dart/3.11 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
41c91dc7-6cd2-44ea-85a6-ba3116dde51b	669cfc05-4701-4332-b604-71cdc2a56679	2026-09-24 08:36:47.152095+00	2026-09-28 07:39:09.221171+00	\N	aal1	\N	2026-09-28 07:39:09.220551	Dart/3.13 (dart:io)	49.149.73.13	\N	\N	\N	\N	\N
aa47f6c1-187b-45c5-af0f-00820e3277d8	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-29 11:48:58.174773+00	2026-03-29 11:48:58.174773+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	14.102.171.185	\N	\N	\N	\N	\N
e0804a46-11d1-4402-a055-82434ea6db43	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-05-27 20:22:22.32976+00	2026-05-27 20:22:22.32976+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	36.255.60.187	\N	\N	\N	\N	\N
e5e1c828-18b5-4340-9918-4f1ae79af67a	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-09-12 12:42:10.238171+00	2026-09-12 12:42:10.238171+00	\N	aal1	\N	\N	Dart/3.11 (dart:io)	103.180.200.134	\N	\N	\N	\N	\N
a8b16fe4-8263-4887-b656-f7f4d04c0dd0	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-08 13:55:24.35684+00	2026-10-08 13:55:24.35684+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	36.255.60.190	\N	\N	\N	\N	\N
b87687bb-8877-4f1f-be7b-fa012e41a1ad	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-08 01:21:56.09518+00	2026-10-08 01:21:56.09518+00	\N	aal1	\N	\N	Dart/3.13 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
632562ac-c555-41fd-97f9-1448b19a83ea	669cfc05-4701-4332-b604-71cdc2a56679	2026-09-28 08:58:46.699331+00	2026-10-03 06:24:19.075294+00	\N	aal1	\N	2026-10-03 06:24:19.07487	Dart/3.13 (dart:io)	36.255.60.189	\N	\N	\N	\N	\N
0d01ccb2-40a8-4203-9c2e-5ab4a68a9433	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-08 01:46:44.044339+00	2026-10-08 03:01:42.132194+00	\N	aal1	\N	2026-10-08 03:01:42.132103	Dart/3.13 (dart:io)	36.255.60.190	\N	\N	\N	\N	\N
7421ec1a-0006-4223-a97c-fe91f6f5084a	681eee4f-a7b6-46ab-87de-6965c92c5711	2026-10-08 11:25:02.1714+00	2026-10-08 15:22:54.554542+00	\N	aal1	\N	2026-10-08 15:22:54.554448	Dart/3.13 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
546c03a8-168b-407b-a27e-32c6e18e83ea	735ae478-e7bf-4db8-b184-bd84a902e870	2026-09-28 06:03:29.67168+00	2026-10-09 00:50:30.682324+00	\N	aal1	\N	2026-10-09 00:50:30.681614	Dart/3.13 (dart:io)	36.255.60.188	\N	\N	\N	\N	\N
\.


--
-- Data for Name: mfa_amr_claims; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."mfa_amr_claims" ("session_id", "created_at", "updated_at", "authentication_method", "id") FROM stdin;
b30a75a6-0f84-4f46-b942-267159c5899f	2026-03-18 10:48:49.986598+00	2026-03-18 10:48:49.986598+00	password	9eff5988-03ff-46ee-84aa-ccde0ba64fe3
fbbcb14c-f6f3-43e7-9260-8704c331d6a2	2026-10-03 08:05:39.232195+00	2026-10-03 08:05:39.232195+00	oauth	b0b587c9-d060-490f-8ddb-de5edc54529f
f934df4d-ebb8-4db0-847c-a5e66dcc603b	2026-10-03 08:05:39.558197+00	2026-10-03 08:05:39.558197+00	oauth	0f429180-c548-423b-b7ff-de94ed9f32b7
e0804a46-11d1-4402-a055-82434ea6db43	2026-05-27 20:22:22.368336+00	2026-05-27 20:22:22.368336+00	oauth	622b58b2-da4c-4268-86c6-0d4bb58a9f84
2e3eb910-22db-4932-a56f-21b648f2d33c	2026-03-18 12:55:14.449244+00	2026-03-18 12:55:14.449244+00	password	138e82ca-6c48-478d-9da8-91479a9ceb9a
b8b7dbf9-0d0c-40c5-9008-84bd59787c03	2026-03-20 23:49:16.483289+00	2026-03-20 23:49:16.483289+00	password	82ca7173-5a1d-477f-8afe-4c2cd1272f99
526288d2-9a68-49a8-9d0b-b7438fe802fc	2026-03-21 01:54:30.338383+00	2026-03-21 01:54:30.338383+00	password	8f0cd1a8-facd-484e-be71-0a4cec5dc809
7c0dd94d-0084-4b70-8a33-f76369376fd1	2026-03-21 02:20:47.829014+00	2026-03-21 02:20:47.829014+00	password	4d488ed4-64a8-41dd-9383-69f151d65717
06d81f00-f3d6-4d77-9879-279daa3539c5	2026-03-29 02:57:44.352186+00	2026-03-29 02:57:44.352186+00	password	7c4fd718-73d7-49a8-a162-0aac633eefaa
115c1937-ca8a-42d3-8585-b2656a772988	2026-03-21 02:38:15.84446+00	2026-03-21 02:38:15.84446+00	password	b86d7197-6565-45ca-bc95-f58954a79ea0
6ec961e1-e272-4618-b5d2-e300f2146f37	2026-03-21 02:42:36.540441+00	2026-03-21 02:42:36.540441+00	password	827e2458-3413-48e4-9393-5e8bf154980f
a6ce61e0-dc1c-4228-aacf-44715671feca	2026-10-06 03:25:42.857447+00	2026-10-06 03:25:42.857447+00	oauth	a9b2bbc1-9b73-486e-84a8-29cbf25dabe7
ff39d202-045f-4a32-b735-629f2fd3d8e1	2026-03-21 03:29:20.818996+00	2026-03-21 03:29:20.818996+00	password	92daac79-0e8e-4f70-bb4f-bfdca0cae4e3
ac33ad91-32c4-45c0-988b-b793eabcd5f4	2026-03-29 04:18:25.395793+00	2026-03-29 04:18:25.395793+00	password	3e2c027a-f6e9-4c57-90cc-dff1cd7ed144
5b4f0401-6daf-4b84-9dd4-46d56b17a1b6	2026-03-29 05:06:55.771961+00	2026-03-29 05:06:55.771961+00	password	a12269ac-b19c-48db-a1c8-32768e67af67
1370dcea-3aea-4647-9757-3cd07eab70b9	2026-05-28 01:23:21.709686+00	2026-05-28 01:23:21.709686+00	oauth	18f00159-577d-4d24-ad9d-f70f2e2f1989
cbd8c6f5-8dba-4ea5-a529-451526315dc6	2026-10-07 02:20:17.218533+00	2026-10-07 02:20:17.218533+00	password	dcad82df-e57b-422d-b9bc-3fef802fd4b6
3627b4c7-2756-4794-a38e-56b6ada4fb8e	2026-03-29 09:21:40.644958+00	2026-03-29 09:21:40.644958+00	oauth	6f791419-e220-4258-bfb4-887d61a5c9d4
2ccd86bf-0b92-4cec-99ad-f86327c68f0a	2026-10-07 03:16:15.585908+00	2026-10-07 03:16:15.585908+00	oauth	eb79f981-c13d-403d-bd4c-6eea1739238e
1a92c02d-dfab-4904-92da-04983239df40	2026-03-29 09:33:33.350844+00	2026-03-29 09:33:33.350844+00	oauth	d6287872-e876-4409-a5cb-2fbf7e8a0f81
fdaa3282-22bb-45fd-a120-147598aff6c3	2026-03-23 05:05:59.924056+00	2026-03-23 05:05:59.924056+00	password	1fe0f60f-9a9c-4f85-81f3-dfa379175478
02fdb0c2-e4d8-4664-8709-89eb19d4e940	2026-03-23 06:30:32.850357+00	2026-03-23 06:30:32.850357+00	password	307cb232-c993-408f-8914-d387469be24e
2c40b624-9f12-4a7e-8ed7-55c9420f6662	2026-03-23 06:45:37.636864+00	2026-03-23 06:45:37.636864+00	password	c5acfc17-1b10-4490-9dc2-c9781963187e
5e4ad18e-4e90-4529-be2a-d5250a9dd5dc	2026-10-07 04:41:51.125157+00	2026-10-07 04:41:51.125157+00	password	889f46c5-4827-4bb6-a40c-94b98ca705f2
351f45dd-44f6-4d95-a6a2-b3d858d8c03c	2026-05-28 06:40:04.549136+00	2026-05-28 06:40:04.549136+00	oauth	b3512636-ce7e-49a1-a8c1-fcc582d88e9f
98b85443-c686-479e-8c15-673e79647568	2026-05-29 10:31:15.346612+00	2026-05-29 10:31:15.346612+00	password	29ddaf3f-bac1-4651-b140-e899de52b8a2
39b284ee-6d69-46f4-996b-ab69ca57ccea	2026-03-23 07:05:22.607624+00	2026-03-23 07:05:22.607624+00	password	47682aad-9c63-4fca-a34d-4aa965c89bc0
5b4bac23-b1ba-48da-b626-8e67991a9520	2026-05-29 11:24:39.176178+00	2026-05-29 11:24:39.176178+00	password	4f5c437c-db13-44b7-b9fc-90a174f8ae8b
aa47f6c1-187b-45c5-af0f-00820e3277d8	2026-03-29 11:48:58.198898+00	2026-03-29 11:48:58.198898+00	password	f0866eab-31e8-4941-a330-337301fdb140
52b658bf-4e7a-4ab6-8678-3f2793bf974f	2026-03-23 13:40:02.625884+00	2026-03-23 13:40:02.625884+00	password	0d75aa05-36fc-4638-8a8a-a12b9d5d4dde
1cd41f02-e4d4-4b19-946e-b251e17c578f	2026-03-29 12:10:12.230608+00	2026-03-29 12:10:12.230608+00	password	6656e7b6-0e91-4bab-b0ef-46b6cb48dc7f
c1426e72-cf1f-477d-8eb1-5a06c7a62e15	2026-03-19 14:50:36.824357+00	2026-03-19 14:50:36.824357+00	password	ca26589f-e2b2-4657-a822-1afa5b6f816c
da5b26b5-1aac-4cd4-8859-6e1f6ceebb4f	2026-03-29 14:19:47.208015+00	2026-03-29 14:19:47.208015+00	password	5f16fdb1-bd6d-47df-874f-2a06989e327c
887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8	2026-05-31 03:27:27.81445+00	2026-05-31 03:27:27.81445+00	password	71fda78a-6a76-4dbd-b1e7-de5a862f7d42
e5e1c828-18b5-4340-9918-4f1ae79af67a	2026-09-12 12:42:10.29578+00	2026-09-12 12:42:10.29578+00	oauth	d745675a-0002-4cfe-882a-afd2e3dec190
a1693680-290a-480c-98c5-e1d1216212e0	2026-04-09 03:29:19.877211+00	2026-04-09 03:29:19.877211+00	password	315be8a1-0e7b-41ba-a146-f5beda9e0c9b
b87687bb-8877-4f1f-be7b-fa012e41a1ad	2026-10-08 01:21:56.139605+00	2026-10-08 01:21:56.139605+00	password	8d463232-2f8d-45f6-99b1-8860a3abc685
0d01ccb2-40a8-4203-9c2e-5ab4a68a9433	2026-10-08 01:46:44.098024+00	2026-10-08 01:46:44.098024+00	password	eaebd888-5a7a-43a9-b5dc-22d1e91f0e69
5f2a5288-26b8-4066-9260-b519828a3afc	2026-09-24 07:59:15.27959+00	2026-09-24 07:59:15.27959+00	password	516cf20f-f8d4-4cd7-8f46-80cc93f8fb71
7421ec1a-0006-4223-a97c-fe91f6f5084a	2026-10-08 11:25:02.21266+00	2026-10-08 11:25:02.21266+00	oauth	07b5d3ab-aaca-41ed-ad61-c82e286f8352
a8b16fe4-8263-4887-b656-f7f4d04c0dd0	2026-10-08 13:55:24.41966+00	2026-10-08 13:55:24.41966+00	password	a91ca195-d640-4918-8ec3-2ef4a3e6ec12
fe2c42e3-d2ac-4290-ace0-381f10788581	2026-05-23 06:16:19.584464+00	2026-05-23 06:16:19.584464+00	oauth	fef10494-b1ac-4ce5-9026-88ad6b1348e9
41c91dc7-6cd2-44ea-85a6-ba3116dde51b	2026-09-24 08:36:47.183358+00	2026-09-24 08:36:47.183358+00	password	6c104030-54b3-4f9a-81ae-019ed1ee2c29
546c03a8-168b-407b-a27e-32c6e18e83ea	2026-09-28 06:03:29.727502+00	2026-09-28 06:03:29.727502+00	password	6137f2f9-0776-476d-a790-dd9542a1f0c5
6eaa5527-1200-4391-99c1-64174d1a61c9	2026-10-09 01:03:59.19063+00	2026-10-09 01:03:59.19063+00	oauth	23b8a1a3-f256-4d8a-89bf-3a179a484afb
632562ac-c555-41fd-97f9-1448b19a83ea	2026-09-28 08:58:46.724758+00	2026-09-28 08:58:46.724758+00	password	441a21ce-d530-4f7d-a84b-fbc46017e972
\.


--
-- Data for Name: mfa_factors; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."mfa_factors" ("id", "user_id", "friendly_name", "factor_type", "status", "created_at", "updated_at", "secret", "phone", "last_challenged_at", "web_authn_credential", "web_authn_aaguid", "last_webauthn_challenge_data") FROM stdin;
\.


--
-- Data for Name: mfa_challenges; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."mfa_challenges" ("id", "factor_id", "created_at", "verified_at", "ip_address", "otp_code", "web_authn_session_data") FROM stdin;
\.


--
-- Data for Name: mfa_recovery_code_sets; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."mfa_recovery_code_sets" ("id", "user_id", "mfa_factor_id", "failed_verification_count", "verification_locked_until", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: mfa_recovery_codes; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."mfa_recovery_codes" ("id", "mfa_recovery_code_set_id", "code_hash", "consumed_at", "created_at") FROM stdin;
\.


--
-- Data for Name: oauth_authorizations; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."oauth_authorizations" ("id", "authorization_id", "client_id", "user_id", "redirect_uri", "scope", "state", "resource", "code_challenge", "code_challenge_method", "response_type", "status", "authorization_code", "created_at", "expires_at", "approved_at", "nonce") FROM stdin;
\.


--
-- Data for Name: oauth_client_states; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."oauth_client_states" ("id", "provider_type", "code_verifier", "created_at") FROM stdin;
\.


--
-- Data for Name: oauth_consents; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."oauth_consents" ("id", "user_id", "client_id", "scopes", "granted_at", "revoked_at") FROM stdin;
\.


--
-- Data for Name: one_time_tokens; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."one_time_tokens" ("id", "user_id", "token_type", "token_hash", "relates_to", "created_at", "updated_at", "expires_at") FROM stdin;
cba969c7-144e-4bee-9762-61fe7159357d	669cfc05-4701-4332-b604-71cdc2a56679	recovery_token	c63be2fb016b7e48fc88241d69e2bf3aba5429a1005cea9575d6a7be	aspillagalibrado@gmail.com	2026-03-28 06:32:21.87514	2026-03-28 06:32:21.87514	\N
\.


--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."refresh_tokens" ("instance_id", "id", "token", "user_id", "revoked", "created_at", "updated_at", "parent", "session_id") FROM stdin;
00000000-0000-0000-0000-000000000000	1	vbrccplvjkj7	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-18 10:48:49.978847+00	2026-03-18 10:48:49.978847+00	\N	b30a75a6-0f84-4f46-b942-267159c5899f
00000000-0000-0000-0000-000000000000	186	ggiaqob4oiv3	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-03-29 09:21:40.628137+00	2026-03-29 09:21:40.628137+00	\N	3627b4c7-2756-4794-a38e-56b6ada4fb8e
00000000-0000-0000-0000-000000000000	296	ncym4yv324fl	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-29 13:23:34.715555+00	2026-05-31 02:47:57.498054+00	yyti7iugkix3	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	188	h67hsck4f3vb	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-03-29 09:33:33.326328+00	2026-03-29 09:33:33.326328+00	\N	1a92c02d-dfab-4904-92da-04983239df40
00000000-0000-0000-0000-000000000000	361	qq7f7ir6topd	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-09-29 02:12:31.315003+00	2026-10-03 08:49:00.455711+00	7ack7izs4cy6	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	302	i4bt7dkg5ziq	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 02:47:57.519236+00	2026-05-31 03:47:21.213143+00	ncym4yv324fl	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	11	uvtkdhh7ttbr	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-18 12:55:14.428494+00	2026-03-18 12:55:14.428494+00	\N	2e3eb910-22db-4932-a56f-21b648f2d33c
00000000-0000-0000-0000-000000000000	306	5ci5xdtmehlb	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-05-31 03:27:27.786705+00	2026-05-31 04:26:49.023912+00	\N	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	307	v6nnwqcmcgar	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 03:47:21.228601+00	2026-05-31 04:46:51.308363+00	i4bt7dkg5ziq	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	69	crl6ifovcond	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-19 14:50:36.812202+00	2026-03-19 15:50:01.684202+00	\N	c1426e72-cf1f-477d-8eb1-5a06c7a62e15
00000000-0000-0000-0000-000000000000	70	zikqluwmvxqe	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-19 15:50:01.710094+00	2026-03-20 11:49:22.024805+00	crl6ifovcond	c1426e72-cf1f-477d-8eb1-5a06c7a62e15
00000000-0000-0000-0000-000000000000	199	lxtl2mqmu5ne	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-29 11:48:58.186568+00	2026-03-29 11:48:58.186568+00	\N	aa47f6c1-187b-45c5-af0f-00820e3277d8
00000000-0000-0000-0000-000000000000	308	jd5cujvfgpl6	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-05-31 04:26:49.054909+00	2026-05-31 05:26:18.906896+00	5ci5xdtmehlb	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	202	nubtjalpcmp7	c341c225-308e-4ff6-84bb-0f1e8732e3b8	f	2026-03-29 12:10:12.222639+00	2026-03-29 12:10:12.222639+00	\N	1cd41f02-e4d4-4b19-946e-b251e17c578f
00000000-0000-0000-0000-000000000000	309	7u5yvc5dfsi6	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 04:46:51.335641+00	2026-05-31 05:46:21.160026+00	v6nnwqcmcgar	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	71	zeqcy4e42ehg	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-20 11:49:22.059978+00	2026-03-20 12:52:52.278857+00	zikqluwmvxqe	c1426e72-cf1f-477d-8eb1-5a06c7a62e15
00000000-0000-0000-0000-000000000000	73	j5t6byp7qu6z	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-20 12:52:52.315812+00	2026-03-20 12:52:52.315812+00	zeqcy4e42ehg	c1426e72-cf1f-477d-8eb1-5a06c7a62e15
00000000-0000-0000-0000-000000000000	310	7q3xs6g5wsjb	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-05-31 05:26:18.922693+00	2026-05-31 06:25:39.071117+00	jd5cujvfgpl6	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	206	viskchxziuwa	db5ff071-d21c-406a-9759-3f1c2a39903c	f	2026-03-29 14:19:47.196492+00	2026-03-29 14:19:47.196492+00	\N	da5b26b5-1aac-4cd4-8859-6e1f6ceebb4f
00000000-0000-0000-0000-000000000000	311	ykc4w4logrzb	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 05:46:21.180544+00	2026-05-31 06:45:48.3798+00	7u5yvc5dfsi6	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	259	q6n75tz5h6iy	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-05-27 20:22:22.345898+00	2026-05-27 20:22:22.345898+00	\N	e0804a46-11d1-4402-a055-82434ea6db43
00000000-0000-0000-0000-000000000000	312	677htsa32gfh	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-05-31 06:25:39.09405+00	2026-05-31 07:25:01.593055+00	7q3xs6g5wsjb	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	313	56imhgxf4xss	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 06:45:48.399217+00	2026-05-31 07:45:18.199427+00	ykc4w4logrzb	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	83	6hydrtgjzn7q	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-20 23:49:16.470267+00	2026-03-21 00:48:42.175363+00	\N	b8b7dbf9-0d0c-40c5-9008-84bd59787c03
00000000-0000-0000-0000-000000000000	84	5bhh3atioscn	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-21 00:48:42.194485+00	2026-03-21 00:48:42.194485+00	6hydrtgjzn7q	b8b7dbf9-0d0c-40c5-9008-84bd59787c03
00000000-0000-0000-0000-000000000000	314	n2mf5y733ojv	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-05-31 07:25:01.615966+00	2026-05-31 08:24:31.969307+00	677htsa32gfh	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	86	qmxpqgo54n26	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-21 01:54:30.298485+00	2026-03-21 01:54:30.298485+00	\N	526288d2-9a68-49a8-9d0b-b7438fe802fc
00000000-0000-0000-0000-000000000000	316	pl4qgho2v6zv	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-05-31 08:24:32.110737+00	2026-05-31 08:24:32.110737+00	n2mf5y733ojv	887acc1b-3ef4-4adc-ad0e-bd9091c5e5c8
00000000-0000-0000-0000-000000000000	87	vqqorvjp527y	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-21 02:20:47.7967+00	2026-03-21 02:20:47.7967+00	\N	7c0dd94d-0084-4b70-8a33-f76369376fd1
00000000-0000-0000-0000-000000000000	315	qkhhwlpwwgap	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 07:45:18.219477+00	2026-05-31 08:44:48.243238+00	56imhgxf4xss	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	90	f5bipz3o2zul	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-21 02:38:15.837774+00	2026-03-21 02:38:15.837774+00	\N	115c1937-ca8a-42d3-8585-b2656a772988
00000000-0000-0000-0000-000000000000	317	w3jch6sedbds	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-31 08:44:48.262494+00	2026-05-31 09:44:15.545789+00	qkhhwlpwwgap	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	93	bncaft436qap	de2219e9-6e80-4b21-a104-b63ae14ad08d	f	2026-03-21 02:42:36.51502+00	2026-03-21 02:42:36.51502+00	\N	6ec961e1-e272-4618-b5d2-e300f2146f37
00000000-0000-0000-0000-000000000000	216	slwvk6qc6s2h	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-04-09 03:29:19.857528+00	2026-04-09 03:29:19.857528+00	\N	a1693680-290a-480c-98c5-e1d1216212e0
00000000-0000-0000-0000-000000000000	97	m4ngvwgs746t	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-21 03:29:20.813916+00	2026-03-22 03:33:34.820204+00	\N	ff39d202-045f-4a32-b735-629f2fd3d8e1
00000000-0000-0000-0000-000000000000	98	nb2fk2i6f5uk	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-03-22 03:33:34.844897+00	2026-03-22 12:11:45.362915+00	m4ngvwgs746t	ff39d202-045f-4a32-b735-629f2fd3d8e1
00000000-0000-0000-0000-000000000000	99	ffa5blbmbqu3	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-22 12:11:45.385227+00	2026-03-22 12:11:45.385227+00	nb2fk2i6f5uk	ff39d202-045f-4a32-b735-629f2fd3d8e1
00000000-0000-0000-0000-000000000000	276	hnsklgmyxh3f	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-05-28 01:23:21.690969+00	2026-05-28 01:23:21.690969+00	\N	1370dcea-3aea-4647-9757-3cd07eab70b9
00000000-0000-0000-0000-000000000000	112	n6nurc3tcadf	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-23 05:05:59.909417+00	2026-03-23 05:05:59.909417+00	\N	fdaa3282-22bb-45fd-a120-147598aff6c3
00000000-0000-0000-0000-000000000000	113	5jb5igvxbb4h	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-23 06:30:32.713938+00	2026-03-23 06:30:32.713938+00	\N	02fdb0c2-e4d8-4664-8709-89eb19d4e940
00000000-0000-0000-0000-000000000000	114	v3kd2aegvtxf	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-23 06:45:37.605652+00	2026-03-23 06:45:37.605652+00	\N	2c40b624-9f12-4a7e-8ed7-55c9420f6662
00000000-0000-0000-0000-000000000000	286	t44wxude55bd	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-05-28 06:40:04.530476+00	2026-05-28 06:40:04.530476+00	\N	351f45dd-44f6-4d95-a6a2-b3d858d8c03c
00000000-0000-0000-0000-000000000000	173	mdsxvkrxtjjn	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	f	2026-03-29 02:57:44.339706+00	2026-03-29 02:57:44.339706+00	\N	06d81f00-f3d6-4d77-9879-279daa3539c5
00000000-0000-0000-0000-000000000000	237	rkl6z6ck276j	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-05-23 06:16:19.563392+00	2026-05-23 06:16:19.563392+00	\N	fe2c42e3-d2ac-4290-ace0-381f10788581
00000000-0000-0000-0000-000000000000	123	ouypjw447utt	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-03-23 07:05:22.603499+00	2026-03-23 07:05:22.603499+00	\N	39b284ee-6d69-46f4-996b-ab69ca57ccea
00000000-0000-0000-0000-000000000000	290	gtg2hx35lvy7	735ae478-e7bf-4db8-b184-bd84a902e870	f	2026-05-29 10:31:15.327691+00	2026-05-29 10:31:15.327691+00	\N	98b85443-c686-479e-8c15-673e79647568
00000000-0000-0000-0000-000000000000	128	c5wnw55h6pvm	db5ff071-d21c-406a-9759-3f1c2a39903c	f	2026-03-23 13:40:02.61206+00	2026-03-23 13:40:02.61206+00	\N	52b658bf-4e7a-4ab6-8678-3f2793bf974f
00000000-0000-0000-0000-000000000000	179	fpt7znskhtyf	db5ff071-d21c-406a-9759-3f1c2a39903c	f	2026-03-29 04:18:25.387306+00	2026-03-29 04:18:25.387306+00	\N	ac33ad91-32c4-45c0-988b-b793eabcd5f4
00000000-0000-0000-0000-000000000000	293	2m4p63liehil	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-29 11:24:39.150348+00	2026-05-29 12:24:04.882865+00	\N	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	182	al4ucxkybukq	db5ff071-d21c-406a-9759-3f1c2a39903c	f	2026-03-29 05:06:55.762215+00	2026-03-29 05:06:55.762215+00	\N	5b4f0401-6daf-4b84-9dd4-46d56b17a1b6
00000000-0000-0000-0000-000000000000	295	yyti7iugkix3	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-05-29 12:24:04.914767+00	2026-05-29 13:23:34.700354+00	2m4p63liehil	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	318	tzy7ng5irhoo	735ae478-e7bf-4db8-b184-bd84a902e870	f	2026-05-31 09:44:15.562313+00	2026-05-31 09:44:15.562313+00	w3jch6sedbds	5b4bac23-b1ba-48da-b626-8e67991a9520
00000000-0000-0000-0000-000000000000	360	7ack7izs4cy6	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-09-29 01:13:10.12661+00	2026-09-29 02:12:31.297327+00	2e2m6egjwzy7	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	359	wrvw6iyrot6s	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-09-28 08:58:46.711526+00	2026-10-03 06:24:19.036123+00	\N	632562ac-c555-41fd-97f9-1448b19a83ea
00000000-0000-0000-0000-000000000000	362	3sqy664pvjkl	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-03 06:24:19.056663+00	2026-10-03 06:24:19.056663+00	wrvw6iyrot6s	632562ac-c555-41fd-97f9-1448b19a83ea
00000000-0000-0000-0000-000000000000	365	ipnbav3qm6t3	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-03 08:05:39.171341+00	2026-10-03 08:05:39.171341+00	\N	fbbcb14c-f6f3-43e7-9260-8704c331d6a2
00000000-0000-0000-0000-000000000000	324	b5jevjegj4ds	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-09-12 12:42:10.274995+00	2026-09-12 12:42:10.274995+00	\N	e5e1c828-18b5-4340-9918-4f1ae79af67a
00000000-0000-0000-0000-000000000000	366	mxhqqht5jdmc	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-03 08:05:39.553879+00	2026-10-03 08:05:39.553879+00	\N	f934df4d-ebb8-4db0-847c-a5e66dcc603b
00000000-0000-0000-0000-000000000000	430	rlhflqyks4va	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-08 01:21:56.11794+00	2026-10-08 01:21:56.11794+00	\N	b87687bb-8877-4f1f-be7b-fa012e41a1ad
00000000-0000-0000-0000-000000000000	432	6ht6n5k7f3dg	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-10-08 01:46:44.080592+00	2026-10-08 03:01:42.09333+00	\N	0d01ccb2-40a8-4203-9c2e-5ab4a68a9433
00000000-0000-0000-0000-000000000000	433	c7fsn3it3bgz	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-08 03:01:42.116942+00	2026-10-08 03:01:42.116942+00	6ht6n5k7f3dg	0d01ccb2-40a8-4203-9c2e-5ab4a68a9433
00000000-0000-0000-0000-000000000000	369	nqoupi53u7zv	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-03 08:49:00.470038+00	2026-10-08 04:05:52.683145+00	qq7f7ir6topd	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	435	lzh7obihwxlm	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 04:05:52.700634+00	2026-10-08 05:05:13.707761+00	nqoupi53u7zv	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	436	vx3dmfiaumgg	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 05:05:13.724452+00	2026-10-08 06:04:41.128495+00	lzh7obihwxlm	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	342	usilysridtnh	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-09-24 07:59:15.248883+00	2026-09-24 07:59:15.248883+00	\N	5f2a5288-26b8-4066-9260-b519828a3afc
00000000-0000-0000-0000-000000000000	437	jzsh5k7n3ak2	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 06:04:41.276236+00	2026-10-08 07:04:02.294442+00	vx3dmfiaumgg	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	438	sjm4uygp3nlu	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 07:04:02.314782+00	2026-10-08 08:03:26.074591+00	jzsh5k7n3ak2	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	439	ndod4hrnxfgz	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 08:03:26.201251+00	2026-10-08 09:02:47.00917+00	sjm4uygp3nlu	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	440	u4vlqq4r2hdd	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 09:02:47.024677+00	2026-10-08 10:02:11.278566+00	ndod4hrnxfgz	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	388	oonmtn37czcs	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-06 03:25:42.846468+00	2026-10-06 03:25:42.846468+00	\N	a6ce61e0-dc1c-4228-aacf-44715671feca
00000000-0000-0000-0000-000000000000	351	hyxy5wcymez2	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-09-24 08:36:47.169438+00	2026-09-28 03:37:21.065864+00	\N	41c91dc7-6cd2-44ea-85a6-ba3116dde51b
00000000-0000-0000-0000-000000000000	352	bxiditj3idi7	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-09-28 03:37:21.085278+00	2026-09-28 06:10:35.730801+00	hyxy5wcymez2	41c91dc7-6cd2-44ea-85a6-ba3116dde51b
00000000-0000-0000-0000-000000000000	441	uhiyp6anygk2	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 10:02:11.296638+00	2026-10-08 11:01:36.422031+00	u4vlqq4r2hdd	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	353	erhkhe6vfdmx	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-09-28 06:03:29.7007+00	2026-09-28 07:02:57.982837+00	\N	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	354	cubcq2cm2wcc	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-09-28 06:10:35.749363+00	2026-09-28 07:39:09.184932+00	bxiditj3idi7	41c91dc7-6cd2-44ea-85a6-ba3116dde51b
00000000-0000-0000-0000-000000000000	356	irsi7h3ojteh	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-09-28 07:39:09.199483+00	2026-09-28 07:39:09.199483+00	cubcq2cm2wcc	41c91dc7-6cd2-44ea-85a6-ba3116dde51b
00000000-0000-0000-0000-000000000000	355	wc4w3ug5d2eh	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-09-28 07:02:57.998175+00	2026-09-28 08:02:24.345965+00	erhkhe6vfdmx	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	445	asqmxhklyiyd	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 11:01:36.441959+00	2026-10-08 12:01:04.50082+00	uhiyp6anygk2	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	357	2e2m6egjwzy7	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-09-28 08:02:24.362251+00	2026-09-29 01:13:10.0825+00	wc4w3ug5d2eh	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	446	f73lcisgnnig	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-08 11:25:02.193104+00	2026-10-08 12:24:25.956068+00	\N	7421ec1a-0006-4223-a97c-fe91f6f5084a
00000000-0000-0000-0000-000000000000	448	2gdsefuwgddd	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-08 12:24:25.973418+00	2026-10-08 13:23:56.114624+00	f73lcisgnnig	7421ec1a-0006-4223-a97c-fe91f6f5084a
00000000-0000-0000-0000-000000000000	398	ojflurum4nun	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-07 03:16:15.575079+00	2026-10-07 04:37:57.625293+00	\N	2ccd86bf-0b92-4cec-99ad-f86327c68f0a
00000000-0000-0000-0000-000000000000	399	hyvuvslynj3j	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-07 04:37:57.638477+00	2026-10-07 04:37:57.638477+00	ojflurum4nun	2ccd86bf-0b92-4cec-99ad-f86327c68f0a
00000000-0000-0000-0000-000000000000	451	jn6loyodfdvb	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-08 13:55:24.387597+00	2026-10-08 13:55:24.387597+00	\N	a8b16fe4-8263-4887-b656-f7f4d04c0dd0
00000000-0000-0000-0000-000000000000	449	kwjbprvd565a	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-08 13:23:56.130889+00	2026-10-08 14:23:24.534978+00	2gdsefuwgddd	7421ec1a-0006-4223-a97c-fe91f6f5084a
00000000-0000-0000-0000-000000000000	403	t7law3ot3zn3	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-07 04:41:51.115095+00	2026-10-07 04:41:51.115095+00	\N	5e4ad18e-4e90-4529-be2a-d5250a9dd5dc
00000000-0000-0000-0000-000000000000	395	el2dxnt3qcda	669cfc05-4701-4332-b604-71cdc2a56679	t	2026-10-07 02:20:17.189+00	2026-10-07 04:45:07.153688+00	\N	cbd8c6f5-8dba-4ea5-a529-451526315dc6
00000000-0000-0000-0000-000000000000	404	xjypagccmygl	669cfc05-4701-4332-b604-71cdc2a56679	f	2026-10-07 04:45:07.172597+00	2026-10-07 04:45:07.172597+00	el2dxnt3qcda	cbd8c6f5-8dba-4ea5-a529-451526315dc6
00000000-0000-0000-0000-000000000000	452	7sgnkvoabmvf	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-08 14:23:24.55422+00	2026-10-08 15:22:54.523325+00	kwjbprvd565a	7421ec1a-0006-4223-a97c-fe91f6f5084a
00000000-0000-0000-0000-000000000000	453	jtl5ggbgfuzq	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-08 15:22:54.537732+00	2026-10-08 15:22:54.537732+00	7sgnkvoabmvf	7421ec1a-0006-4223-a97c-fe91f6f5084a
00000000-0000-0000-0000-000000000000	447	mxm6sqkalcqx	735ae478-e7bf-4db8-b184-bd84a902e870	t	2026-10-08 12:01:04.518317+00	2026-10-09 00:50:30.648696+00	asqmxhklyiyd	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	456	gm44zelus6jl	735ae478-e7bf-4db8-b184-bd84a902e870	f	2026-10-09 00:50:30.656405+00	2026-10-09 00:50:30.656405+00	mxm6sqkalcqx	546c03a8-168b-407b-a27e-32c6e18e83ea
00000000-0000-0000-0000-000000000000	458	3a47knax4qff	681eee4f-a7b6-46ab-87de-6965c92c5711	t	2026-10-09 01:03:59.181147+00	2026-10-09 04:21:04.495479+00	\N	6eaa5527-1200-4391-99c1-64174d1a61c9
00000000-0000-0000-0000-000000000000	459	g6dran7ldpio	681eee4f-a7b6-46ab-87de-6965c92c5711	f	2026-10-09 04:21:04.517856+00	2026-10-09 04:21:04.517856+00	3a47knax4qff	6eaa5527-1200-4391-99c1-64174d1a61c9
\.


--
-- Data for Name: sso_providers; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."sso_providers" ("id", "resource_id", "created_at", "updated_at", "disabled") FROM stdin;
\.


--
-- Data for Name: saml_providers; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."saml_providers" ("id", "sso_provider_id", "entity_id", "metadata_xml", "metadata_url", "attribute_mapping", "created_at", "updated_at", "name_id_format") FROM stdin;
\.


--
-- Data for Name: saml_relay_states; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."saml_relay_states" ("id", "sso_provider_id", "request_id", "for_email", "redirect_to", "created_at", "updated_at", "flow_state_id") FROM stdin;
\.


--
-- Data for Name: scim_tokens; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."scim_tokens" ("id", "sso_provider_id", "token_hash", "prefix", "created_at", "expires_at", "revoked_at", "last_used_at") FROM stdin;
\.


--
-- Data for Name: scim_users; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."scim_users" ("id", "sso_provider_id", "user_id", "resource", "created_at", "updated_at", "deleted_at") FROM stdin;
\.


--
-- Data for Name: sso_domains; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."sso_domains" ("id", "sso_provider_id", "domain", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: webauthn_challenges; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."webauthn_challenges" ("id", "user_id", "challenge_type", "session_data", "created_at", "expires_at") FROM stdin;
\.


--
-- Data for Name: webauthn_credentials; Type: TABLE DATA; Schema: auth; Owner: supabase_auth_admin
--

COPY "auth"."webauthn_credentials" ("id", "user_id", "credential_id", "public_key", "attestation_type", "aaguid", "sign_count", "transports", "backup_eligible", "backed_up", "friendly_name", "created_at", "updated_at", "last_used_at") FROM stdin;
\.


--
-- Data for Name: regions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."regions" ("id", "name", "code", "base_delivery_fee", "sla_goal_mins", "is_active", "metadata", "created_at") FROM stdin;
f6be79a8-f981-4666-ab12-4240c635e47d	Carrascal	CRL	20.00	50	t	{}	2026-03-29 04:39:18.320084+00
ff38b3ce-c527-41a1-ae24-63bdd8e8e85f	Cantilan	CTL	15.00	45	t	{}	2026-03-29 04:39:18.320084+00
a8b448c2-3391-4739-b043-d76fd75f1910	Madrid	MAD	15.00	45	t	{}	2026-03-29 04:39:18.320084+00
8d7af04e-68a2-498f-8be9-986878a965ee	Carmen	CRM	15.00	45	t	{}	2026-03-29 04:39:18.320084+00
8147dd4e-3171-4b36-a5d0-534ce7418097	Lanuza	LNZ	25.00	60	t	{}	2026-03-29 04:39:18.320084+00
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."profiles" ("id", "username", "full_name", "role", "town", "owner_id", "phone", "station_name", "barangay", "complete_address", "landmark", "lat", "lng", "created_at", "email", "average_rating", "review_count", "is_open", "station_description", "station_logo_url", "commission_rate", "primary_water_type", "station_photo_url", "bio_description", "price_per_gallon", "water_type", "owner_phone", "vehicle_type", "license_number", "avatar_url", "first_name", "last_name", "mi", "suffix", "latitude", "longitude", "is_online", "station_id", "reliability_score", "total_deliveries", "flagged_count", "region_id", "purok", "zip_code", "preferred_water_type", "station_availability", "is_suspended", "suspended_at", "suspended_reason", "admin_tier", "updated_at") FROM stdin;
db5ff071-d21c-406a-9759-3f1c2a39903c	jaylord	Jaylord Buiza	rider	Cantilan	669cfc05-4701-4332-b604-71cdc2a56679	09487571340	\N	Parang	\N	\N	\N	\N	2026-03-23 06:47:39.238694+00	jaylord@gmail.com	0.00	0	t	\N	\N	5.00	\N	\N	\N	25.00	\N	\N	Multicab	123456	https://ormmjxtbwosnraijphra.supabase.co/storage/v1/object/public/avatars/avatar_db5ff071-d21c-406a-9759-3f1c2a39903c.png	Jaylord	Buiza			9.3390565	125.9725556	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
681eee4f-a7b6-46ab-87de-6965c92c5711	user_681eee4f	Jherald Kim G. Aspillaga	customer	Cantilan	\N	09487571340	\N	Magosilom	Magosilom, Cantilan, Surigao Del Sur	Gate 4	\N	\N	2026-03-29 09:21:40.459588+00	jheraldkima@gmail.com	0.00	0	t	\N	\N	5.00	\N	\N	\N	25.00	\N	\N	\N	\N	\N	Jherald Kim	Aspillaga	G.	\N	9.33735688384894	125.968304876133	t	\N	5.00	0	0	\N	\N	8317	Purified Water	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
669cfc05-4701-4332-b604-71cdc2a56679	librado	Librado P Aspillaga Jr.	owner	Cantilan	\N	09487571340	Aspillaga Water Refilling Station	Parang	Purok 11, Parang Cantilan, Surigao Del Sur	\N	\N	\N	2026-03-18 10:45:15.644503+00	aspillagalibrado@gmail.com	0.00	0	t	Dapit sa tulay	\N	5.00	Purified Water	https://ormmjxtbwosnraijphra.supabase.co/storage/v1/object/public/avatars/cover_669cfc05-4701-4332-b604-71cdc2a56679.jpg	\N	20.00	\N	\N	\N	\N	https://ormmjxtbwosnraijphra.supabase.co/storage/v1/object/public/avatars/avatar_669cfc05-4701-4332-b604-71cdc2a56679.jpg	Librado	Aspillaga	P	Jr.	9.27786071148106	125.932032614612	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
4fb7557c-826c-4d67-a4ff-1f5bef0189ce	molejon_cantilan	L. Molejon Water Refilling Station	owner	Cantilan	\N	\N	L. Molejon Water Refilling Station	\N	8XPH+7QX, R. Azarcon Street, Cantilan, 8317 Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	molejon.cantilan@erefill.local	0.00	0	t	Local refill station in Cantilan.	\N	5.00	Purified Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.38	125.94	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
2ebdbe41-6685-417a-8843-915117ed6e5d	orothel_cantilan	Orothel Water Refilling Station	owner	Cantilan	\N	\N	Orothel Water Refilling Station	\N	Cantilan, Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	orothel.cantilan@erefill.local	0.00	0	t	Offers walk-in and delivery services (7:00 AM-7:00 PM).	\N	5.00	Purified Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.39	125.93	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
e25aa023-db2e-4e3c-9003-3a8f30b8fea3	waterkaw_cantilan	WATER Kaw! Purified water & Refilling Station	owner	Cantilan	\N	\N	WATER Kaw! Purified water & Refilling Station	\N	8XR4+CWF, Magasang Barangay Rd, Cantilan, Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	waterkaw.cantilan@erefill.local	0.00	0	t	Operates Monday-Saturday 7:30 AM–7:30 PM, Sunday 8:30 AM–7:30 PM.	\N	5.00	Purified Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.3667	125.9667	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
de2219e9-6e80-4b21-a104-b63ae14ad08d	jovert	Jovert Ropol	rider	Cantilan	669cfc05-4701-4332-b604-71cdc2a56679	09123456789	Aspillaga Water Refilling Station	Poblacion	\N	\N	\N	\N	2026-03-21 02:42:11.352212+00	jovert@gmail.com	0.00	0	t	\N	\N	5.00	\N	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.277674499999998	125.93248575	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
aece23c3-1302-431d-aeea-a6b7fe0bd9a0	saysay	saysay	rider	\N	c341c225-308e-4ff6-84bb-0f1e8732e3b8	\N	\N	\N	\N	\N	\N	\N	2026-03-29 02:57:44.254747+00	saysay@gmail.com	0.00	0	t	\N	\N	5.00	\N	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
64f965d6-d068-427d-9895-99944b60c47e	rlwater_cantilan	RL Water Refilling Station	owner	Cantilan	\N	\N	RL Water Refilling Station	\N	Cantilan, Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	rlwater.cantilan@erefill.local	0.00	0	t	Facebook presence indicates operation in the area.	\N	5.00	Purified Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.4	125.92	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
c341c225-308e-4ff6-84bb-0f1e8732e3b8	jvaspillaga	jv G Aspillaga 	owner	Cantilan	\N	\N	Tubigan Ni Jv	\N	Minipark, Parang, Cantilan, Surigao, Del Sur	\N	\N	\N	2026-03-29 02:52:33.885062+00	jv@gmail.com	0.00	0	t	\N	\N	5.00	\N	https://ormmjxtbwosnraijphra.supabase.co/storage/v1/object/public/avatars/cover_c341c225-308e-4ff6-84bb-0f1e8732e3b8.jpg	\N	25.00	\N	\N	\N	\N	https://ormmjxtbwosnraijphra.supabase.co/storage/v1/object/public/avatars/avatar_c341c225-308e-4ff6-84bb-0f1e8732e3b8.png	\N	\N	\N	\N	\N	\N	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
876fdc46-ea42-4cf2-b2bc-0c4a54a99a52	perch_cantilan	PERCH Water Refilling Station	owner	Cantilan	\N	\N	PERCH Water Refilling Station	\N	8XM8+GPV Pag-Antayan, Cantilan, Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	perch.cantilan@erefill.local	0.00	0	t	Open 24 hours daily.	\N	5.00	Purified Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.35	125.95	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
df9c89ce-4e04-4dee-934c-4eb043688b20	mwd_madrid	Madrid Water District	owner	Madrid	\N	\N	Madrid Water District (Public Utility)	\N	Purok 4, Brgy Quirino, Madrid, Surigao del Sur	\N	\N	\N	2026-03-19 01:43:52.841646+00	mwd.madrid@erefill.local	0.00	0	t	Public utility provider in Madrid.	\N	5.00	Mineral Water	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	9.24	125.89	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	\N	2026-10-08 14:17:48.666521+00
735ae478-e7bf-4db8-b184-bd84a902e870	platform_admin	Platform Admin	admin	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-29 10:29:48.766672+00	admin@gmail.com	0.00	0	t	\N	\N	5.00	\N	\N	\N	25.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	\N	5.00	0	0	\N	\N	\N	\N	open	f	\N	\N	super	2026-10-08 14:17:48.666521+00
\.


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."audit_logs" ("id", "created_at", "actor_id", "action", "entity_type", "entity_id", "old_value", "new_value", "metadata") FROM stdin;
dc6c8d07-5dcb-4d17-a013-7656b879bc04	2026-03-29 12:10:54.753492+00	c341c225-308e-4ff6-84bb-0f1e8732e3b8	STATUS_CHANGE	order	3afe4ca4-2432-4d31-9b1b-e3d249bbd69c	{"status": "pending"}	{"status": "accepted"}	\N
f4f3cfab-d679-41f5-b043-cc2e65fcc6d7	2026-03-29 14:19:21.789889+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	{"status": "pending"}	{"status": "accepted"}	\N
ce2d5f07-a1c6-480d-8279-033ec71c051c	2026-03-29 14:19:27.670458+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	{"status": "accepted"}	{"status": "preparing"}	\N
7cab84f4-0f21-444e-a2bb-5b52704e75c5	2026-03-29 14:19:31.292075+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	{"status": "preparing"}	{"status": "out_for_delivery"}	\N
a3e87088-9882-4e98-b5f2-1da20e799539	2026-04-09 03:29:45.510743+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	702f471e-392a-47dd-a992-ab262738f20f	{"status": "pending"}	{"status": "accepted"}	\N
0477ea5f-70e7-4f9c-b9a0-3fe9d0e5cde9	2026-04-09 03:29:55.617725+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	702f471e-392a-47dd-a992-ab262738f20f	{"status": "accepted"}	{"status": "preparing"}	\N
f61b330d-f03c-40ae-b656-ac3dc2ba22d4	2026-04-09 03:30:02.191965+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	702f471e-392a-47dd-a992-ab262738f20f	{"status": "preparing"}	{"status": "out_for_delivery"}	\N
8bbd0813-553c-45bf-9f72-adab15c337b4	2026-05-29 10:31:46.338103+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	false	true	{"reason": "Toggled from admin desktop"}
77d3fb3c-b79c-44b6-ad55-a8ddcd035382	2026-05-29 10:31:56.495671+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	true	false	{"reason": "Toggled from admin desktop"}
1b4af018-8f54-4729-a1b2-d2399a5101cf	2026-05-29 10:33:56.724717+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	feature_gcash_enabled	true	false	{"reason": "Toggled from admin desktop"}
7b575522-1ef3-4fd6-9c52-0296775b1941	2026-05-29 10:49:01.423128+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
9f490830-22d6-420a-a01d-bf94959f5b31	2026-05-29 10:49:01.423128+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	2.5	2.00	{"reason": "Updated from admin revenue console"}
c6e7e8fb-5719-4da8-b8f5-d293ccd0e793	2026-05-29 10:49:01.423128+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0	0.00	{"reason": "Updated from admin revenue console"}
5d14ade4-c6fd-46ba-89a7-b1d751d7b501	2026-05-29 10:51:27.346895+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	feature_gcash_enabled	false	true	{"reason": "Toggled from admin desktop"}
7a005c71-ac30-40e9-9163-deee5792bb20	2026-05-29 11:58:43.071522+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
96a09604-eac5-4a28-8673-ebe69927427d	2026-05-29 11:58:43.071522+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	2.00	1.25	{"reason": "Updated from admin revenue console"}
fd6a22e1-47cf-48b9-9a69-879ccf3c8dfa	2026-05-29 11:58:43.071522+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.00	20.00	{"reason": "Updated from admin revenue console"}
ff798261-026f-4a08-9b43-d45b522401dd	2026-05-31 02:48:53.963307+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
e6668e91-32f1-4a1c-99bb-7350b4b42496	2026-05-31 02:48:53.963307+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	1.25	1.00	{"reason": "Updated from admin revenue console"}
0dfe1bcd-0aeb-43d9-b4b5-0564bd7fc4b0	2026-05-31 02:48:53.963307+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	20.00	20.00	{"reason": "Updated from admin revenue console"}
b924cf85-b421-40ca-b849-ed10c3f381a3	2026-05-31 02:51:21.886354+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
6fb7add0-4446-475c-8f9e-c7809d579f41	2026-05-31 02:51:21.886354+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	1.00	0.25	{"reason": "Updated from admin revenue console"}
bffb442c-a7fc-47e8-b874-fad813cefd5c	2026-05-31 02:51:21.886354+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	20.00	20.00	{"reason": "Updated from admin revenue console"}
89e2268b-0a1f-48e2-bf91-9a71a05f2c9e	2026-05-31 03:02:11.247283+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_update_user_password	user	6922fff9-e1e5-435f-bcdd-ca07b11beb6d	\N	{"password_reset": true}	{"reason": null}
7dfba1ae-2a4f-4e6c-ab0a-b1c755efd382	2026-09-28 06:05:25.954524+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	false	{"reason": "Toggled from admin desktop"}
1ce15044-670d-429c-b5a3-5187fd3c567e	2026-09-28 06:05:32.496717+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	false	true	{"reason": "Toggled from admin desktop"}
e374b17b-f1bb-4686-aa30-192b57abc075	2026-09-28 06:06:44.126872+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
267931bd-88e8-4727-864d-31d01b2933eb	2026-09-28 06:06:44.126872+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.25	0.25	{"reason": "Updated from admin revenue console"}
e43bd53c-2d43-43d0-97a7-766a496a640b	2026-09-28 06:06:44.126872+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	20.00	20.00	{"reason": "Updated from admin revenue console"}
5f440b2a-dc42-4206-bbd5-9036f327197b	2026-09-28 06:07:35.535627+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
5b7717e7-eae7-47e0-87d7-5a8101816c6d	2026-09-28 06:07:35.535627+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.25	0.25	{"reason": "Updated from admin revenue console"}
6344d132-0a7b-454a-b40f-02ba20050dc9	2026-09-28 06:07:35.535627+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	20.00	0.50	{"reason": "Updated from admin revenue console"}
b0a76406-a1de-478a-818e-b5252d6763d2	2026-10-03 08:50:10.043412+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	false	true	{"reason": "Toggled from admin desktop"}
a11e28fd-444d-4542-b1ef-9060283d4488	2026-10-03 08:52:11.869382+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	d0fb2d0c-3450-40c1-8e76-98e537c2d2ea	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
87488712-a006-49f9-a804-e7d8f1d85278	2026-10-03 08:52:45.166016+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	d960db92-f726-4f96-8c77-1b535696a6b9	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
e576e7fd-e4fa-429f-b3e9-3b5ca9fed726	2026-10-03 08:52:45.166016+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_station	station	d960db92-f726-4f96-8c77-1b535696a6b9	\N	\N	{"reason": "Deleted by admin"}
a8f25414-37d9-4491-bf7f-1d64e9149fde	2026-10-03 08:54:23.807866+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	true	false	{"reason": "Toggled from admin desktop"}
54098ef3-21dd-4b79-b19c-3b1dfabcc5ad	2026-10-08 04:25:33.1119+00	735ae478-e7bf-4db8-b184-bd84a902e870	STATUS_CHANGE	order	702f471e-392a-47dd-a992-ab262738f20f	{"status": "out_for_delivery"}	{"status": "cancelled"}	\N
618fa965-c5e5-4ed3-b510-b25740c3bec7	2026-10-08 04:25:33.1119+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_cancel_order	order	702f471e-392a-47dd-a992-ab262738f20f	{"id": "702f471e-392a-47dd-a992-ab262738f20f", "items": [], "notes": null, "status": "out_for_delivery", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679", "quantity": 1, "rider_id": null, "subtotal": 20.00, "region_id": null, "created_at": "2026-04-09T03:28:35.229179+00:00", "updated_at": "2026-04-09T03:29:45.510743+00:00", "water_type": null, "customer_id": "681eee4f-a7b6-46ab-87de-6965c92c5711", "total_price": null, "delivery_fee": 25.00, "delivery_lat": null, "delivery_lng": null, "platform_fee": 0.00, "station_name": "Aspillaga Water Refilling Station", "total_amount": 45.00, "customer_name": "Jherald Kim G Aspillaga", "payment_error": null, "retry_allowed": true, "container_type": null, "customer_phone": "09487571340", "payment_method": "cod", "payment_status": "pending", "idempotency_key": "795c7666-6236-4b72-a123-5458cd76a952", "customer_address": "Purok 11, Parang, Cantilan, Surigao Del Sur", "assigned_rider_id": "db5ff071-d21c-406a-9759-3f1c2a39903c", "customer_barangay": "Parang", "customer_landmark": "May tulay", "delivery_latitude": null, "payment_proof_url": null, "delivery_longitude": null, "delivery_photo_url": null, "payment_checkout_id": null, "actual_completion_at": null, "payment_checkout_url": null, "customer_municipality": "Cantilan", "delivery_signature_url": null, "empty_gallons_returned": 0}	{"status": "cancelled"}	{"reason": ""}
ddb1e8ac-ab2b-4634-87ab-6506a219bc3e	2026-10-08 04:35:21.196078+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	false	{"reason": "Updated from admin revenue console"}
178e7448-556b-4ba4-b61b-fdeccf014b85	2026-10-08 04:35:21.196078+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.25	0.00	{"reason": "Updated from admin revenue console"}
1beeb190-3ca0-4e5d-9a43-6011dd062704	2026-10-08 04:35:21.196078+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.50	0.50	{"reason": "Updated from admin revenue console"}
6c359720-fdb1-477a-9288-a399bfbd3e6a	2026-10-08 04:36:01.04625+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	false	true	{"reason": "Updated from admin revenue console"}
591995b6-79c7-41d8-bdfd-43b05fdd3961	2026-10-08 04:36:01.04625+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.00	0.25	{"reason": "Updated from admin revenue console"}
34cffb39-cb0e-46f2-a4d3-bf41d5c2cab5	2026-10-08 04:36:01.04625+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.50	0.50	{"reason": "Updated from admin revenue console"}
7059b555-b814-49e8-9cf3-2cc2bb941056	2026-10-08 05:07:42.41414+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from admin revenue console"}
53d46753-608b-4f5a-ba2c-175e3db63514	2026-10-08 05:07:42.41414+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.25	0.00	{"reason": "Updated from admin revenue console"}
d6c0eb1e-38ac-4371-98dd-e7b037b23e21	2026-10-08 05:07:42.41414+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.50	0.50	{"reason": "Updated from admin revenue console"}
8a9f9229-0245-42f1-ab2e-53c9d646caed	2026-10-08 05:09:10.205848+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	aee6596e-0799-41c4-bb4f-337a308f76e4	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
dd8f8b2e-dfb5-4630-abc8-db16dd653223	2026-10-08 05:09:10.205848+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_station	station	aee6596e-0799-41c4-bb4f-337a308f76e4	\N	\N	{"reason": "Deleted by admin"}
41524b0d-2c2c-4c6e-871f-363e2e562116	2026-10-08 05:11:49.075306+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	6d5f6446-6384-4fd7-bfda-33e882268408	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
857f7a69-518d-4ba7-b4bd-aa5be3896232	2026-10-08 05:11:49.075306+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_station	station	6d5f6446-6384-4fd7-bfda-33e882268408	\N	\N	{"reason": "Deleted by admin"}
bb64e117-46f3-4a8c-837e-05e94d1d9ad7	2026-10-08 07:43:28.988072+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from system settings"}
2dc9cfa7-36cc-409a-983f-9415efeb7089	2026-10-08 07:43:28.988072+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.00	0.50	{"reason": "Updated from system settings"}
eccc6f3c-539b-4434-9996-dd3a5965740f	2026-10-08 07:43:28.988072+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.50	0.50	{"reason": "Updated from system settings"}
abb26722-495d-4ee2-a645-5f633bb78281	2026-10-08 07:56:26.330037+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	909b863a-1c20-47b5-9774-4172e85b9b8c	\N	\N	{"role": "customer", "reason": "Deleted by admin"}
a4fe2c9d-8da3-4ee2-b6ba-1b768b628585	2026-10-08 07:56:42.749701+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	6922fff9-e1e5-435f-bcdd-ca07b11beb6d	\N	\N	{"role": "customer", "reason": "Deleted by admin"}
b10fa25c-8538-41d3-88cc-016084609d21	2026-10-08 07:57:05.749652+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	9dbfb599-c6fe-40d5-a048-9bebe68b8f00	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
ae3450af-5ef4-4999-bd59-34607f9d21ed	2026-10-08 07:57:10.896434+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	860bd924-4ba4-4e4e-93b8-9b6d54b3be45	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
e34755b2-8855-44ab-92ae-fde54ba62320	2026-10-08 07:57:30.741695+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_delete_user	user	7f1a801a-b58d-4e1c-b317-ae04ef30d823	\N	\N	{"role": "owner", "reason": "Deleted by admin"}
b3a756c3-cf0e-4530-8a54-7fb1f11bdf08	2026-10-08 07:59:53.510044+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_enabled	true	true	{"reason": "Updated from system settings"}
382ea25d-0b43-4b56-9779-ee6359458eb1	2026-10-08 07:59:53.510044+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_percent	0.50	0.00	{"reason": "Updated from system settings"}
28e1b32e-c035-4742-bc0c-9f2d9bdd22e2	2026-10-08 07:59:53.510044+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	platform_fee_fixed	0.50	0.50	{"reason": "Updated from system settings"}
9df25707-ff5b-4727-a086-3bdce294bcb7	2026-10-08 08:00:20.074076+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	false	true	{"reason": "Toggled from system settings"}
4e34349a-909a-4b7c-ba92-ace35b521fcf	2026-10-08 08:00:28.420921+00	735ae478-e7bf-4db8-b184-bd84a902e870	admin_set_system_config	system_config	maintenance_mode	true	false	{"reason": "Toggled from system settings"}
1df8079c-9ce5-4108-8fac-be5b46b20155	2026-10-08 10:46:25.088298+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	c887f19c-2f1d-4ce5-b870-2945c46b0698	{"status": "pending"}	{"status": "accepted"}	\N
eb410cf0-3ae6-4e49-a005-270faec092af	2026-10-08 10:49:37.990686+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	c887f19c-2f1d-4ce5-b870-2945c46b0698	{"status": "accepted"}	{"status": "preparing"}	\N
a9b0bc16-2935-4cb3-9009-f16749a62f4b	2026-10-08 10:49:44.790319+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	c887f19c-2f1d-4ce5-b870-2945c46b0698	{"status": "preparing"}	{"status": "ready_for_pickup"}	\N
143109ae-dda4-4757-b180-c69a21e70e5a	2026-10-08 10:55:18.982674+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	c887f19c-2f1d-4ce5-b870-2945c46b0698	{"status": "ready_for_pickup"}	{"status": "assigned_to_rider"}	\N
4cc9aabc-10af-40f0-b620-e96d10887ad4	2026-10-08 10:56:11.82527+00	db5ff071-d21c-406a-9759-3f1c2a39903c	STATUS_CHANGE	order	c887f19c-2f1d-4ce5-b870-2945c46b0698	{"status": "assigned_to_rider"}	{"status": "out_for_delivery"}	\N
fc010c05-3c5d-4598-a650-bee6bda4b7d0	2026-10-08 13:56:18.090564+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	ff69bbcc-3ef2-40ce-89a5-7f51cdaff4f2	{"status": "pending"}	{"status": "accepted"}	\N
23622fb1-0bba-4521-9dab-d838d9d70d9a	2026-10-08 13:56:36.429921+00	669cfc05-4701-4332-b604-71cdc2a56679	STATUS_CHANGE	order	5fbdd8c7-bc07-46b5-9b2f-e3a7676d4a84	{"status": "pending"}	{"status": "accepted"}	\N
\.


--
-- Data for Name: chat_rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."chat_rooms" ("id", "room_type", "reference_id", "status", "owner_id", "title", "created_at", "updated_at", "archived_at", "metadata") FROM stdin;
47a128f8-f62d-4505-8bf8-d35166a6e3f8	order_delivery	c887f19c-2f1d-4ce5-b870-2945c46b0698	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-10-08 11:31:20.171714+00	2026-10-08 11:31:20.171714+00	\N	{}
8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	order_delivery	2cbe9448-73fa-4945-b142-4beb717e3939	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-03-28 09:48:46.43676+00	2026-03-29 05:05:34.152961+00	\N	{}
55800245-34cf-4abe-8071-e30db23f68ef	customer_support	\N	active	669cfc05-4701-4332-b604-71cdc2a56679	Support Enquiry - Aspillaga Water Refilling Station 	2026-03-28 10:48:47.916413+00	2026-03-29 09:38:59.523767+00	\N	{}
9d0337f7-9de1-4c12-8c73-e08793885b6e	customer_support	\N	active	669cfc05-4701-4332-b604-71cdc2a56679	Support Enquiry - Aspillaga Water Refilling Station	2026-03-29 11:13:21.579247+00	2026-03-29 11:16:03.10613+00	\N	{}
9399e5f4-4352-4d6c-bec6-a8bb7e91814d	customer_support	\N	active	c341c225-308e-4ff6-84bb-0f1e8732e3b8	Support Enquiry - Tubigan Ni Jv	2026-03-29 02:54:14.308506+00	2026-03-29 12:16:57.766491+00	\N	{}
8665780b-827e-454a-9b76-beeb64ebe66f	order_delivery	ed89a831-bc93-4c97-96bc-e7fcf68cf639	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-03-23 13:56:22.725039+00	2026-05-23 00:47:55.576561+00	\N	{}
a121ffa8-5f58-41d8-b526-d8ac49b09de6	customer_support	\N	active	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	Support Enquiry - L. Molejon Water Refilling Station	2026-05-23 01:25:16.285311+00	2026-05-23 01:25:16.285311+00	\N	{}
6a0e44bf-eff2-4dcd-b341-6de61043e792	order_delivery	4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-05-27 19:15:33.185059+00	2026-05-27 20:27:19.789016+00	\N	{}
e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	order_delivery	702f471e-392a-47dd-a992-ab262738f20f	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-09-14 13:15:32.316791+00	2026-09-23 12:04:57.527426+00	\N	{}
83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	order_delivery	5fbdd8c7-bc07-46b5-9b2f-e3a7676d4a84	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-09-24 08:23:13.550914+00	2026-09-24 08:25:40.17538+00	\N	{}
5fbfb84b-dbff-44e4-997a-49c81b8d3724	order_delivery	3dda6e15-4847-49b7-b1ec-534a7464cecd	active	669cfc05-4701-4332-b604-71cdc2a56679	Order Delivery	2026-10-07 04:40:08.731784+00	2026-10-07 04:41:03.744406+00	\N	{}
514996e7-6884-40df-9a1b-450b09120125	customer_support	\N	active	\N	Support Enquiry - ERWAN GAS REFILLING STATION	2026-03-28 09:56:00.167968+00	2026-10-08 07:57:10.896434+00	\N	{}
\.


--
-- Data for Name: chat_participants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."chat_participants" ("id", "room_id", "user_id", "role_in_room", "joined_at", "last_read_at", "is_muted", "metadata") FROM stdin;
03239d36-23bf-4b39-8074-7bcc0a1b07e2	8665780b-827e-454a-9b76-beeb64ebe66f	db5ff071-d21c-406a-9759-3f1c2a39903c	rider	2026-03-23 13:56:22.725039+00	\N	f	{}
7276835e-2b50-4adf-b06f-66a081e0f532	8665780b-827e-454a-9b76-beeb64ebe66f	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-03-23 13:56:22.725039+00	\N	f	{}
fde77350-4491-49c8-9fb3-d1b1db56e0c4	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	de2219e9-6e80-4b21-a104-b63ae14ad08d	rider	2026-03-28 09:48:46.43676+00	\N	f	{}
df1dc132-56dd-49a8-9441-51d63c603180	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-03-28 09:48:46.43676+00	\N	f	{}
bcae4b20-7df5-4bd0-9756-0cef71c8d5b1	55800245-34cf-4abe-8071-e30db23f68ef	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-03-28 10:48:47.916413+00	\N	f	{}
f2321ab0-683a-4ab4-844b-98ee52f79e12	9399e5f4-4352-4d6c-bec6-a8bb7e91814d	c341c225-308e-4ff6-84bb-0f1e8732e3b8	owner	2026-03-29 02:54:14.308506+00	\N	f	{}
224f27de-5ac7-4168-92c3-b771e66ecde9	9d0337f7-9de1-4c12-8c73-e08793885b6e	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-03-29 11:13:21.579247+00	\N	f	{}
d9caa03b-f39a-4ea2-a785-12ef0ac6fdc6	9d0337f7-9de1-4c12-8c73-e08793885b6e	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-03-29 11:13:21.579247+00	\N	f	{}
dd897df8-adf8-4397-abec-a6222ff450f2	a121ffa8-5f58-41d8-b526-d8ac49b09de6	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-05-23 01:25:16.285311+00	\N	f	{}
e47ec5bc-359c-4b6a-ad8d-00e6d0a22cb5	a121ffa8-5f58-41d8-b526-d8ac49b09de6	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	owner	2026-05-23 01:25:16.285311+00	\N	f	{}
f56be2d9-bb9e-4c15-821b-e8e7779b14b0	6a0e44bf-eff2-4dcd-b341-6de61043e792	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-05-27 19:15:33.185059+00	\N	f	{}
d4330b65-bc5e-4e2c-afa5-5d20ea8da805	6a0e44bf-eff2-4dcd-b341-6de61043e792	db5ff071-d21c-406a-9759-3f1c2a39903c	rider	2026-05-27 19:15:33.185059+00	\N	f	{}
30fa28ac-54e4-4acd-afb4-e2fe887071f7	6a0e44bf-eff2-4dcd-b341-6de61043e792	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-05-27 19:15:33.185059+00	\N	f	{}
b973946c-4b4a-4f6a-8e40-eb04c3a4824b	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-09-14 13:15:32.316791+00	\N	f	{}
bb626ccb-cc14-46d6-83a4-903d72e11a3c	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	db5ff071-d21c-406a-9759-3f1c2a39903c	rider	2026-09-14 13:15:32.316791+00	\N	f	{}
4a95c298-f1af-43a7-b3ae-0e42cb6cb751	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-09-14 13:15:32.316791+00	\N	f	{}
b2ecfbce-2abf-49ca-8bb9-2288d50cd532	83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-09-24 08:23:13.550914+00	\N	f	{}
d4236014-838a-40bb-962f-e12dd4438e57	83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-09-24 08:23:13.550914+00	\N	f	{}
ab3ea993-8c52-4516-a1ea-18e8bdc29a72	5fbfb84b-dbff-44e4-997a-49c81b8d3724	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-10-07 04:40:08.731784+00	\N	f	{}
0647a63b-3904-4edd-bb55-b4ed1b3e590b	5fbfb84b-dbff-44e4-997a-49c81b8d3724	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-10-07 04:40:08.731784+00	\N	f	{}
195ed829-095a-4ed7-9c53-33d9ef753650	47a128f8-f62d-4505-8bf8-d35166a6e3f8	681eee4f-a7b6-46ab-87de-6965c92c5711	customer	2026-10-08 11:31:20.171714+00	\N	f	{}
55e2bc8d-5be3-4bfe-83d1-d34099cfc3b8	47a128f8-f62d-4505-8bf8-d35166a6e3f8	db5ff071-d21c-406a-9759-3f1c2a39903c	rider	2026-10-08 11:31:20.171714+00	\N	f	{}
1ee530d5-29aa-4f3f-807b-db5d5af2a1cf	47a128f8-f62d-4505-8bf8-d35166a6e3f8	669cfc05-4701-4332-b604-71cdc2a56679	owner	2026-10-08 11:31:20.171714+00	\N	f	{}
\.


--
-- Data for Name: customer_addresses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."customer_addresses" ("id", "customer_id", "label", "complete_address", "barangay", "town", "landmark", "latitude", "longitude", "is_default", "created_at", "updated_at") FROM stdin;
4ed52d28-8568-4711-89f1-b1d16e3275fc	681eee4f-a7b6-46ab-87de-6965c92c5711	Home	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	Cantilan	May tulay	9.2776304	125.9320872	f	2026-10-07 17:37:08.873733+00	2026-10-08 08:49:22.851274+00
aee0a854-f15e-49fc-9d6d-b3e53620767e	681eee4f-a7b6-46ab-87de-6965c92c5711	University	Magosilom, Cantilan, Surigao Del Sur	Magosilom	Cantilan	Gate 4	9.33735688384894	125.96830487613339	t	2026-10-09 04:30:51.773493+00	2026-10-09 04:30:51.773493+00
\.


--
-- Data for Name: customer_payment_methods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."customer_payment_methods" ("id", "customer_id", "type", "label", "masked_value", "gateway_payment_method_id", "card_brand", "card_last4", "status", "is_default", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."orders" ("id", "customer_id", "owner_id", "rider_id", "water_type", "container_type", "quantity", "total_price", "status", "delivery_lat", "delivery_lng", "created_at", "delivery_fee", "payment_method", "payment_proof_url", "assigned_rider_id", "updated_at", "station_name", "items", "subtotal", "total_amount", "customer_name", "customer_phone", "customer_address", "customer_barangay", "customer_landmark", "customer_municipality", "idempotency_key", "delivery_latitude", "delivery_longitude", "delivery_photo_url", "delivery_signature_url", "actual_completion_at", "payment_status", "payment_error", "retry_allowed", "region_id", "notes", "empty_gallons_returned", "payment_checkout_id", "payment_checkout_url", "platform_fee") FROM stdin;
716b9554-ba1f-4e72-954d-3c79af195374	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-03 06:55:21.035204+00	25.00	cod	\N	\N	2026-10-03 06:55:21.035204+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	dafdff1a-8b73-4a88-8704-3f9c76e0f2f4	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
8bf6fac9-46e8-4c8b-a681-ff4561ef594b	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-03 12:39:41.78889+00	25.00	cod	\N	\N	2026-10-03 12:39:41.78889+00	Aspillaga Water Refilling Station	[]	40.00	65.66	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	48e83191-217b-40c0-8efb-19d38b29f621	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.66
b58a09c8-6720-4ee8-a598-26dd0c2ea5d7	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-06 03:26:43.889761+00	25.00	cod	\N	\N	2026-10-06 03:26:43.889761+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	67949504-b97e-4b26-9138-09a61ae644c8	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
c1de8b5e-ca24-47fe-bda5-c6792df85c95	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-06 03:38:42.532631+00	25.00	cod	\N	\N	2026-10-06 03:38:42.532631+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	5a197451-0b4f-4e42-8188-3ad4ea202431	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
3ef07e0b-6258-451e-98d0-ef357695a0df	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-06 05:00:21.938951+00	25.00	cod	\N	\N	2026-10-06 05:00:21.938951+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	b41fa13a-a67d-4731-9298-625b0743d792	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
2cbe9448-73fa-4945-b142-4beb717e3939	\N	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	out_for_delivery	\N	\N	2026-03-23 04:45:24.14362+00	50.00	cod	\N	de2219e9-6e80-4b21-a104-b63ae14ad08d	2026-03-23 04:45:24.14362+00		[]	100.00	150.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	pending	\N	t	\N	\N	0	\N	\N	0.00
ed89a831-bc93-4c97-96bc-e7fcf68cf639	\N	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	out_for_delivery	\N	\N	2026-03-23 10:01:34.13027+00	50.00	cod	\N	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-23 10:01:34.13027+00	Aspillaga Water Refilling Station 	[]	40.00	90.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	pending	\N	t	\N	\N	0	\N	\N	0.00
c887f19c-2f1d-4ce5-b870-2945c46b0698	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	out_for_delivery	\N	\N	2026-10-08 10:44:21.491318+00	25.00	cod	\N	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 18:56:11.549263+00	Aspillaga Water Refilling Station	[]	20.00	45.50	Jherald Kim G. Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	c5b9b2fe-9655-489d-96fa-20177778a68d	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.50
5e0ce279-3475-46ee-8cc5-c91a272f1652	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-07 03:10:14.643014+00	25.00	cod	\N	\N	2026-10-07 03:10:14.643014+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	cf379740-9697-4ed3-be18-ce4aa3c2e1ca	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
3dda6e15-4847-49b7-b1ec-534a7464cecd	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-07 04:40:03.698506+00	25.00	cod	\N	\N	2026-10-07 04:40:03.698506+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	82301468-be8c-4ec8-9a89-a1faa24a1d67	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	out_for_delivery	\N	\N	2026-03-29 14:17:23.986099+00	25.00	cod	\N	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-29 14:19:21.789889+00	Aspillaga Water Refilling Station	[]	20.00	45.00	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	a4461b7c-9810-4189-b081-fb1628946b27	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.00
355052d6-2cd7-447f-9259-c3d789cac60a	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	pending	\N	\N	2026-10-07 18:15:35.361255+00	25.00	cod	\N	\N	2026-10-07 18:15:35.361255+00	Aspillaga Water Refilling Station	[]	40.00	65.66	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	1673f65d-7c9a-4b94-a94f-c7d985b4a06d	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.66
702f471e-392a-47dd-a992-ab262738f20f	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	cancelled	\N	\N	2026-04-09 03:28:35.229179+00	25.00	cod	\N	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 04:25:33.1119+00	Aspillaga Water Refilling Station	[]	20.00	45.00	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	795c7666-6236-4b72-a123-5458cd76a952	\N	\N	\N	\N	\N	failed	\N	t	\N	\N	0	\N	\N	0.00
3afe4ca4-2432-4d31-9b1b-e3d249bbd69c	\N	c341c225-308e-4ff6-84bb-0f1e8732e3b8	\N	\N	\N	1	\N	accepted	\N	\N	2026-03-29 02:54:32.102308+00	50.00	cod	\N	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	2026-03-29 12:10:54.753492+00	Tubigan Ni Jv	[]	25.00	75.00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	pending	\N	t	\N	\N	0	\N	\N	0.00
ff69bbcc-3ef2-40ce-89a5-7f51cdaff4f2	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	accepted	\N	\N	2026-10-08 00:46:38.135341+00	25.00	cod	\N	\N	2026-10-08 21:56:19.354731+00	Aspillaga Water Refilling Station	[]	20.00	45.61	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	bac6500a-eb64-48c5-91d2-01ecc211d3a0	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	0.61
5fbdd8c7-bc07-46b5-9b2f-e3a7676d4a84	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	\N	\N	\N	1	\N	accepted	\N	\N	2026-09-24 08:23:03.980019+00	25.00	cod	\N	\N	2026-10-08 21:56:40.66571+00	Aspillaga Water Refilling Station	[]	20.00	65.11	Jherald Kim G Aspillaga	09487571340	Purok 11, Parang, Cantilan, Surigao Del Sur	Parang	May tulay	Cantilan	20a6e4c9-2274-4b49-b5ed-c68ae82d2e7e	\N	\N	\N	\N	\N	pending	\N	t	\N		0	\N	\N	20.11
\.


--
-- Data for Name: disputes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."disputes" ("id", "order_id", "reporter_id", "reason", "description", "status", "evidence_url", "resolution_notes", "resolved_by", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: dm_riders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."dm_riders" ("id", "owner_id", "linked_user_id", "full_name", "phone", "email", "commission_per_gallon", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: dm_deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."dm_deliveries" ("id", "owner_id", "rider_id", "delivery_date", "gallons", "price_per_gallon", "expenses", "notes", "empty_gallons_returned", "commission", "owner_profit", "credit_amount", "is_synced", "local_id", "created_at", "updated_at") FROM stdin;
6ac57e84-0a33-4984-b273-ad55411d8ffd	669cfc05-4701-4332-b604-71cdc2a56679	\N	2026-05-28	100.00	20.00	150.00	\N	100.00	0.00	\N	20.00	f	6ac57e84-0a33-4984-b273-ad55411d8ffd	2026-05-28 01:54:08.506368+00	2026-05-28 01:54:08.506368+00
\.


--
-- Data for Name: dm_credits; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."dm_credits" ("id", "owner_id", "rider_id", "delivery_id", "credit_type", "debtor_name", "amount", "paid_amount", "is_paid", "payment_date", "notes", "is_synced", "local_id", "created_at", "updated_at") FROM stdin;
309f8ca4-e870-46cc-b00a-75987f208b5c	669cfc05-4701-4332-b604-71cdc2a56679	\N	6ac57e84-0a33-4984-b273-ad55411d8ffd	customer	Customer (Delivery 6ac57e84)	20.00	0.00	f	\N	\N	f	309f8ca4-e870-46cc-b00a-75987f208b5c	2026-05-28 01:54:09.217099+00	2026-05-28 01:54:09.217099+00
\.


--
-- Data for Name: dm_inventory; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."dm_inventory" ("id", "owner_id", "transaction_date", "transaction_type", "gallons", "notes", "delivery_id", "created_at") FROM stdin;
\.


--
-- Data for Name: domain_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."domain_events" ("id", "event_type", "payload", "actor_id", "metadata", "created_at") FROM stdin;
0db2b337-5edd-44f8-a488-15b62071bde1	DELIVERY_SYNC_FAILED	{"error": "Bad state: databaseFactory not initialized\\ndatabaseFactory is only initialized when using sqflite. When using `sqflite_common_ffi`\\nYou must call `databaseFactory = databaseFactoryFfi;` before using global openDatabase API\\n", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679"}	669cfc05-4701-4332-b604-71cdc2a56679	{"level": "error", "is_web": false, "order_id": null, "platform": "windows", "rider_id": null}	2026-05-31 02:25:00.913862+00
7fb486fc-0190-4cc4-9c44-3ee9f9e515bd	DELIVERY_SYNC_FAILED	{"error": "Bad state: databaseFactory not initialized\\ndatabaseFactory is only initialized when using sqflite. When using `sqflite_common_ffi`\\nYou must call `databaseFactory = databaseFactoryFfi;` before using global openDatabase API\\n", "owner_id": "669cfc05-4701-4332-b604-71cdc2a56679"}	669cfc05-4701-4332-b604-71cdc2a56679	{"level": "error", "is_web": false, "order_id": null, "platform": "windows", "rider_id": null}	2026-05-31 02:25:00.928728+00
\.


--
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."expenses" ("id", "owner_id", "category", "amount", "description", "expense_date", "created_at") FROM stdin;
\.


--
-- Data for Name: favorites; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."favorites" ("id", "user_id", "station_id", "created_at") FROM stdin;
212d6ad6-f879-4410-a1d3-dbae8dc47a61	681eee4f-a7b6-46ab-87de-6965c92c5711	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-03 13:10:56.045575+00
6f316f4a-8cd4-4cb6-98f1-283c7e6b8e9b	681eee4f-a7b6-46ab-87de-6965c92c5711	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	2026-10-09 01:11:42.529581+00
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."products" ("id", "owner_id", "name", "description", "price", "image_url", "category", "is_available", "created_at", "stock_level", "low_stock_threshold", "preparation_minutes", "container_size") FROM stdin;
a42f51e1-0c9b-45ae-843d-cb793ac9528e	669cfc05-4701-4332-b604-71cdc2a56679	Purified Water	Purified Water refill service	20.00	\N	Purified	t	2026-09-23 13:00:51.223383+00	98	10	15	5 letters
\.


--
-- Data for Name: inventory_ledger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."inventory_ledger" ("id", "product_id", "change_amount", "reason", "actor_id", "created_at") FROM stdin;
a306107c-ef80-46ee-a397-11956eb68707	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-09-24 08:23:03.980019+00
b4ad1293-3167-4c49-bb61-5a21e9e8db72	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-03 06:55:21.035204+00
3d627055-5c27-4885-bb21-906623e38abf	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-2	SALE	\N	2026-10-03 12:39:41.78889+00
4e8da70f-d1f9-4a3b-9cbd-06a6d9c07804	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-06 03:26:43.889761+00
1991a7fc-fd0c-4809-9c3f-c95190aa6932	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-06 03:38:42.532631+00
c9403a13-06d8-453e-a7f8-80fae5568b46	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-06 05:00:21.938951+00
e5068a53-f3d2-4306-9108-0cdfdbd6401c	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-07 03:10:14.643014+00
a5e8a8ac-d4fa-41e8-9896-bad7620791e7	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-07 04:40:03.698506+00
3a8bb86a-08dd-487f-82be-b4a1e573d0c1	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-2	SALE	\N	2026-10-07 18:15:35.361255+00
b234dd83-df9d-4bba-984b-105e4b59adf6	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-08 00:46:38.135341+00
5c75b860-2ce3-497a-9144-51b26f78b433	a42f51e1-0c9b-45ae-843d-cb793ac9528e	-1	SALE	\N	2026-10-08 10:44:21.491318+00
\.


--
-- Data for Name: ledger_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."ledger_entries" ("id", "account_id", "order_id", "amount", "entry_type", "description", "created_at", "metadata") FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."messages" ("id", "room_id", "sender_id", "content", "message_type", "metadata", "is_read", "read_by", "reply_to", "created_at", "updated_at", "deleted_at", "status", "retry_count", "error_message", "is_sms_fallback_triggered") FROM stdin;
06d8b487-b4b7-419a-b5d8-62f31d59f9e8	8665780b-827e-454a-9b76-beeb64ebe66f	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-03-23 13:56:22.725039+00	2026-03-23 13:56:22.725039+00	\N	sent	0	\N	f
dfd03a70-28e0-4c3b-b5e8-ff72474bc683	55800245-34cf-4abe-8071-e30db23f68ef	669cfc05-4701-4332-b604-71cdc2a56679	Thank you!	text	{}	f	[]	\N	2026-03-29 09:38:59.523767+00	2026-03-29 09:38:59.523767+00	\N	sent	0	\N	f
3954975a-9c2e-4d0c-9c2c-8e00e01eb5d8	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-03-28 09:48:46.43676+00	2026-03-28 09:48:46.43676+00	\N	sent	0	\N	f
44859b08-692f-42ab-8671-42b3199ccb25	514996e7-6884-40df-9a1b-450b09120125	\N	Support chat started. You can now message the station owner directly.	system	{}	f	[]	\N	2026-03-28 09:56:00.167968+00	2026-03-28 09:56:00.167968+00	\N	sent	0	\N	f
4e595173-f6b1-4627-8bb3-a7a3b2759393	8665780b-827e-454a-9b76-beeb64ebe66f	db5ff071-d21c-406a-9759-3f1c2a39903c	I'm 5 minutes away	text	{}	t	["12d9ad95-5063-4f61-a8c7-5ea17f51a102", "669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-03-28 10:47:01.032054+00	2026-03-29 09:39:06.273646+00	\N	sent	0	\N	f
d6b537e3-5c1f-41b5-b967-41560b97a06f	9d0337f7-9de1-4c12-8c73-e08793885b6e	\N	Support chat started. You can now message the station owner directly.	system	{}	f	[]	\N	2026-03-29 11:13:21.579247+00	2026-03-29 11:13:21.579247+00	\N	sent	0	\N	f
081ce3c8-1dc8-4e42-847c-a756c5d0b857	9d0337f7-9de1-4c12-8c73-e08793885b6e	681eee4f-a7b6-46ab-87de-6965c92c5711	hello HAHAHAHA	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-03-29 11:13:37.873146+00	2026-03-29 11:15:37.224374+00	\N	sent	0	\N	f
cf7f3062-f330-47e4-806e-bab4d54a3c0b	9d0337f7-9de1-4c12-8c73-e08793885b6e	669cfc05-4701-4332-b604-71cdc2a56679	sana nga	text	{}	t	["681eee4f-a7b6-46ab-87de-6965c92c5711"]	\N	2026-03-29 11:16:03.10613+00	2026-03-29 11:22:44.637823+00	\N	sent	0	\N	f
b8cfc311-d7c4-4973-85b8-8caf3e19c579	9399e5f4-4352-4d6c-bec6-a8bb7e91814d	c341c225-308e-4ff6-84bb-0f1e8732e3b8	omg ka	text	{}	f	[]	\N	2026-03-29 12:16:57.766491+00	2026-03-29 12:16:57.766491+00	\N	sent	0	\N	f
36b1b19d-ce44-4c1a-8b96-7800b19cef60	55800245-34cf-4abe-8071-e30db23f68ef	\N	Support chat started. You can now message the station owner directly.	system	{}	f	[]	\N	2026-03-28 10:48:47.916413+00	2026-03-28 10:48:47.916413+00	\N	sent	0	\N	f
b7f35824-2aa7-409b-b17a-f3b53e939636	8665780b-827e-454a-9b76-beeb64ebe66f	669cfc05-4701-4332-b604-71cdc2a56679	sure?	text	{}	t	["db5ff071-d21c-406a-9759-3f1c2a39903c"]	\N	2026-03-29 09:39:14.108748+00	2026-03-29 14:32:05.37165+00	\N	sent	0	\N	f
5da2060a-a41b-427d-a6b3-3b4c5688b8cc	9399e5f4-4352-4d6c-bec6-a8bb7e91814d	\N	Support chat started. You can now message the station owner directly.	system	{}	f	[]	\N	2026-03-29 02:54:14.308506+00	2026-03-29 02:54:14.308506+00	\N	sent	0	\N	f
dc2fb123-9c41-4271-91d0-012a5ad63baf	8665780b-827e-454a-9b76-beeb64ebe66f	db5ff071-d21c-406a-9759-3f1c2a39903c	oo naman	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-03-29 14:32:09.351118+00	2026-04-08 04:44:54.318943+00	\N	sent	0	\N	f
0b9a6255-3032-4de0-a86b-c4929ebc97e4	8665780b-827e-454a-9b76-beeb64ebe66f	db5ff071-d21c-406a-9759-3f1c2a39903c	I'm 5 minutes away	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-05-23 00:47:55.576561+00	2026-05-23 00:51:26.47458+00	\N	sent	0	\N	f
57f5046d-7758-4eaf-a1c1-e4880834bb30	a121ffa8-5f58-41d8-b526-d8ac49b09de6	\N	Support chat started. You can now message the station owner directly.	system	{}	f	[]	\N	2026-05-23 01:25:16.285311+00	2026-05-23 01:25:16.285311+00	\N	sent	0	\N	f
27b533ff-32f8-4a82-b641-0409cf348dcb	6a0e44bf-eff2-4dcd-b341-6de61043e792	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-05-27 19:15:33.185059+00	2026-05-27 19:15:33.185059+00	\N	sent	0	\N	f
24fc3eb1-11b6-432b-9924-ba981c6a9fea	6a0e44bf-eff2-4dcd-b341-6de61043e792	681eee4f-a7b6-46ab-87de-6965c92c5711	What are your hours?	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-05-27 20:27:19.789016+00	2026-05-28 03:27:08.095878+00	\N	sent	0	\N	f
dbef0d2a-efc6-4aa1-a563-4bf838706033	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-09-14 13:15:32.316791+00	2026-09-14 13:15:32.316791+00	\N	sent	0	\N	f
a688c6a1-3c8e-492d-ba15-72360add9069	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	681eee4f-a7b6-46ab-87de-6965c92c5711	Where are you now?	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679", "db5ff071-d21c-406a-9759-3f1c2a39903c"]	\N	2026-09-22 13:41:51.263336+00	2026-09-24 08:19:23.256824+00	\N	sent	0	\N	f
b4e0d2b1-4aa2-422c-841e-a32ec8b4849f	e4e27cb9-137b-4d68-bd9e-bc6ba62a6d8b	669cfc05-4701-4332-b604-71cdc2a56679	hello	text	{}	t	["681eee4f-a7b6-46ab-87de-6965c92c5711", "db5ff071-d21c-406a-9759-3f1c2a39903c"]	\N	2026-09-23 12:04:57.527426+00	2026-09-24 08:19:23.256824+00	\N	sent	0	\N	f
51fde2a9-9c94-4db9-80fd-23417dc09cce	83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-09-24 08:23:13.550914+00	2026-09-24 08:23:13.550914+00	\N	sent	0	\N	f
2d2cea60-73c8-4325-af4c-fda60569c6c6	83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	681eee4f-a7b6-46ab-87de-6965c92c5711	Leave at the door	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-09-24 08:23:18.019141+00	2026-09-24 08:24:17.960213+00	\N	sent	0	\N	f
04291e71-9198-43a1-ae9e-d32373b8fc26	83b3bf58-77e9-4b8c-9516-0d7d6fb7202e	669cfc05-4701-4332-b604-71cdc2a56679	okay	text	{}	t	["681eee4f-a7b6-46ab-87de-6965c92c5711"]	\N	2026-09-24 08:25:40.17538+00	2026-10-03 13:00:38.432679+00	\N	sent	0	\N	f
51ccf268-c2c6-44ea-bf71-140c2ce5c477	5fbfb84b-dbff-44e4-997a-49c81b8d3724	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-10-07 04:40:08.731784+00	2026-10-07 04:40:08.731784+00	\N	sent	0	\N	f
958779ad-45c9-470e-9efa-f3700af088ae	5fbfb84b-dbff-44e4-997a-49c81b8d3724	681eee4f-a7b6-46ab-87de-6965c92c5711	okay naako order?	text	{}	t	["669cfc05-4701-4332-b604-71cdc2a56679"]	\N	2026-10-07 04:40:14.638384+00	2026-10-07 04:40:55.942369+00	\N	sent	0	\N	f
ae4c0004-80aa-4e48-b0b6-ade088b73070	5fbfb84b-dbff-44e4-997a-49c81b8d3724	669cfc05-4701-4332-b604-71cdc2a56679	oo goods na	text	{}	t	["681eee4f-a7b6-46ab-87de-6965c92c5711"]	\N	2026-10-07 04:41:03.744406+00	2026-10-07 04:41:18.449602+00	\N	sent	0	\N	f
11a13dfc-8f8b-4e5d-9601-c1acf20f26fe	9399e5f4-4352-4d6c-bec6-a8bb7e91814d	\N	Sanaol boang	text	{}	t	["c341c225-308e-4ff6-84bb-0f1e8732e3b8"]	\N	2026-03-29 02:54:20.821479+00	2026-10-08 07:56:42.749701+00	\N	sent	0	\N	f
e32a425a-e9d4-43f1-88c8-71a649284ca5	47a128f8-f62d-4505-8bf8-d35166a6e3f8	\N	Order chat started. Use this channel for delivery updates and directions.	system	{}	f	[]	\N	2026-10-08 11:31:20.171714+00	2026-10-08 11:31:20.171714+00	\N	sent	0	\N	f
66ca7c4d-3e2c-440a-b455-0f9d82101ef3	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	I am at the gate	text	{}	f	[]	\N	2026-03-28 10:12:07.408889+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
10a5452e-9535-4a3f-80f0-39b90485dfb4	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Leave at the door	text	{}	f	[]	\N	2026-03-28 10:12:11.685619+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
2553ab95-591f-4dc2-9c1a-474355a6959c	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Where are you now?	text	{}	f	[]	\N	2026-03-28 10:12:17.050382+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
8d767fe1-df66-4450-968f-1ebfcd7abd9d	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Ring the doorbell	text	{}	f	[]	\N	2026-03-28 10:24:50.05343+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
c51c7827-165f-400a-b6d3-dab1f160bb4c	8665780b-827e-454a-9b76-beeb64ebe66f	\N	Please ring the doorbell	text	{}	t	["db5ff071-d21c-406a-9759-3f1c2a39903c"]	\N	2026-03-23 14:03:51.148892+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
dfabb8a1-5717-40c7-852f-83757f400c22	8665780b-827e-454a-9b76-beeb64ebe66f	\N	ETA please?	text	{}	t	["db5ff071-d21c-406a-9759-3f1c2a39903c"]	\N	2026-03-28 10:14:34.420713+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
4ab9b176-ba14-4604-bfb6-a6f99be2c983	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Where are you now?	text	{}	f	[]	\N	2026-03-28 10:47:40.009739+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
8c9376ed-5a76-4c5d-9306-504168fea8dc	55800245-34cf-4abe-8071-e30db23f68ef	\N	Is my order ready?	text	{}	f	[]	\N	2026-03-28 10:48:59.118744+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
03042ad9-254e-453a-920b-430cf488fb4d	55800245-34cf-4abe-8071-e30db23f68ef	\N	Thank you!	text	{}	f	[]	\N	2026-03-28 14:55:34.830422+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
f658f052-33ee-4551-b707-bac0f28666e7	8908c23f-fe7b-4fac-8060-aba7ca9d1eb9	\N	Where are you now?	text	{}	f	[]	\N	2026-03-29 05:05:34.152961+00	2026-03-29 07:15:34.533532+00	\N	sent	0	\N	f
\.


--
-- Data for Name: operational_metrics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."operational_metrics" ("id", "station_id", "metric_name", "metric_value", "snapshot_time") FROM stdin;
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."order_items" ("id", "order_id", "product_name", "quantity", "price_at_purchase", "product_id", "subtotal", "created_at") FROM stdin;
44da58bf-d1c2-4943-be79-8cc83d0efdd6	ed89a831-bc93-4c97-96bc-e7fcf68cf639	Purified Water	2	20.00	\N	40.00	2026-03-23 10:01:34.56158+00
03fb95d8-35b5-4a7d-82ba-c591e30fcc73	3afe4ca4-2432-4d31-9b1b-e3d249bbd69c	Purified Water	1	25.00	\N	25.00	2026-03-29 02:54:32.250255+00
7e09097b-6849-42c7-990c-fa7c40442969	4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4	Purified Water	1	20.00	\N	20.00	2026-03-29 14:17:23.986099+00
7653c195-239e-4187-8f5e-c82c696eb93a	702f471e-392a-47dd-a992-ab262738f20f	Purified Water	1	20.00	\N	20.00	2026-04-09 03:28:35.229179+00
3636e7d0-d4d5-4cc4-8f11-e4f78c13b735	5fbdd8c7-bc07-46b5-9b2f-e3a7676d4a84	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-09-24 08:23:03.980019+00
f3850456-aba7-4226-9872-001d47080501	716b9554-ba1f-4e72-954d-3c79af195374	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-03 06:55:21.035204+00
e82702f2-2583-4712-b3ee-3c742ce2c99c	8bf6fac9-46e8-4c8b-a681-ff4561ef594b	Purified Water	2	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	40.00	2026-10-03 12:39:41.78889+00
1af6acdc-ac52-426e-9575-ca0cdfb14bf5	b58a09c8-6720-4ee8-a598-26dd0c2ea5d7	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-06 03:26:43.889761+00
f38d8d50-1feb-4efb-9b8d-c4490e7d319c	c1de8b5e-ca24-47fe-bda5-c6792df85c95	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-06 03:38:42.532631+00
4bc3c079-4d1d-41b8-8a5f-29549a27be39	3ef07e0b-6258-451e-98d0-ef357695a0df	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-06 05:00:21.938951+00
28bbba27-5565-4c60-b697-9f96e13499a3	5e0ce279-3475-46ee-8cc5-c91a272f1652	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-07 03:10:14.643014+00
4f92dcbb-897d-4b35-b277-7b68e5d797a4	3dda6e15-4847-49b7-b1ec-534a7464cecd	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-07 04:40:03.698506+00
f1acf458-2a6e-4a5f-b21f-bfa105283ff9	355052d6-2cd7-447f-9259-c3d789cac60a	Purified Water	2	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	40.00	2026-10-07 18:15:35.361255+00
3cbd6e62-ca42-467c-9910-210b5a9c60a3	ff69bbcc-3ef2-40ce-89a5-7f51cdaff4f2	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-08 00:46:38.135341+00
40a80b68-412a-458c-9378-6f559cd6aaf1	c887f19c-2f1d-4ce5-b870-2945c46b0698	Purified Water	1	20.00	a42f51e1-0c9b-45ae-843d-cb793ac9528e	20.00	2026-10-08 10:44:21.491318+00
\.


--
-- Data for Name: owner_inventory_ledger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."owner_inventory_ledger" ("id", "owner_id", "tx_type", "gallons", "product_id", "order_id", "notes", "actor_id", "created_at") FROM stdin;
f0284d43-ccd2-4a1b-9883-3fdd09ffa343	669cfc05-4701-4332-b604-71cdc2a56679	load_filled	11	a42f51e1-0c9b-45ae-843d-cb793ac9528e	\N	\N	669cfc05-4701-4332-b604-71cdc2a56679	2026-09-24 08:18:05.89183+00
3b9be6ac-ddb2-48fc-a92a-c76465bcb0bc	669cfc05-4701-4332-b604-71cdc2a56679	load_empty	26	\N	\N	\N	669cfc05-4701-4332-b604-71cdc2a56679	2026-09-24 08:18:21.059313+00
\.


--
-- Data for Name: owner_payout_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."owner_payout_accounts" ("id", "owner_id", "type", "label", "masked_value", "encrypted_account_ref", "provider_name", "status", "is_default", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: owner_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."owner_settings" ("id", "owner_id", "base_delivery_fee", "price_per_gallon", "created_at", "updated_at", "service_radius_km", "max_concurrent_orders", "empty_gallons_stock", "enabled_payment_methods") FROM stdin;
c222cbda-6a97-461d-ba60-95b95967e810	df9c89ce-4e04-4dee-934c-4eb043688b20	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
0e838c3c-f1c4-4b4e-9dac-c31d99268c8f	e25aa023-db2e-4e3c-9003-3a8f30b8fea3	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
b823eb23-b397-4c2e-b65f-88293fa50ed7	876fdc46-ea42-4cf2-b2bc-0c4a54a99a52	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
f18781be-8432-4058-9620-cec915eea06c	4fb7557c-826c-4d67-a4ff-1f5bef0189ce	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
e5817561-f54a-47e5-923a-3d8c1bd011db	2ebdbe41-6685-417a-8843-915117ed6e5d	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
0a569a5f-bc73-479e-8f38-6cf77d586cbc	64f965d6-d068-427d-9895-99944b60c47e	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
d9072249-1c21-463b-a13f-708a39ba7003	c341c225-308e-4ff6-84bb-0f1e8732e3b8	25	15	2026-03-29 12:25:19.653499+00	2026-03-29 12:25:19.653499+00	10	20	0	{cod,gcash,maya,card}
5d3a864d-0a2a-475b-ac3d-8600547717d5	669cfc05-4701-4332-b604-71cdc2a56679	25	15	2026-03-29 12:25:19.653499+00	2026-09-24 08:18:21.059313+00	10	20	26	{cod,gcash,maya,card}
\.


--
-- Data for Name: payment_checkouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."payment_checkouts" ("id", "order_id", "customer_id", "owner_id", "provider", "payment_method", "provider_checkout_id", "checkout_url", "amount", "currency", "status", "raw_response", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: payment_webhook_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."payment_webhook_events" ("id", "checkout_id", "order_id", "customer_id", "owner_id", "provider", "provider_checkout_id", "event_type", "provider_status", "processing_status", "error_message", "raw_payload", "created_at", "processed_at", "provider_event_id") FROM stdin;
\.


--
-- Data for Name: quick_replies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."quick_replies" ("id", "rider_id", "label", "message_text", "sort_order", "is_active", "created_at", "updated_at") FROM stdin;
0deb70de-5060-49b8-a042-65cb054fc01d	db5ff071-d21c-406a-9759-3f1c2a39903c	I'm 5 minutes away	Hi! I'm about 5 minutes away with your order. Please get ready!	1	t	2026-03-23 06:47:39.238694+00	2026-03-23 06:47:39.238694+00
1dffe694-4682-4039-97c6-64df1ce02a47	db5ff071-d21c-406a-9759-3f1c2a39903c	I have arrived	I've arrived at your location. Please come out to receive your order.	2	t	2026-03-23 06:47:39.238694+00	2026-03-23 06:47:39.238694+00
a26516f3-2708-48ef-a10f-91a5b88b065d	db5ff071-d21c-406a-9759-3f1c2a39903c	Can't find house	I'm having trouble finding your exact house. Can you provide more specific directions?	3	t	2026-03-23 06:47:39.238694+00	2026-03-23 06:47:39.238694+00
300995c0-40ff-41ea-a860-665278e9da6e	db5ff071-d21c-406a-9759-3f1c2a39903c	Order delivered	Your order has been delivered. Thank you for choosing us!	4	t	2026-03-23 06:47:39.238694+00	2026-03-23 06:47:39.238694+00
fd460742-bbc2-49a6-857c-3b9c08a41721	db5ff071-d21c-406a-9759-3f1c2a39903c	Running late	Sorry, I'm running a bit late due to traffic. I'll be there soon!	5	t	2026-03-23 06:47:39.238694+00	2026-03-23 06:47:39.238694+00
52928c4a-19ce-4659-a991-2803c99d2de9	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	I'm 5 minutes away	Hi! I'm about 5 minutes away with your order. Please get ready!	1	t	2026-03-29 02:57:44.254747+00	2026-03-29 02:57:44.254747+00
c67d2d60-e550-44b0-8e7c-16e605e1abb2	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	I have arrived	I've arrived at your location. Please come out to receive your order.	2	t	2026-03-29 02:57:44.254747+00	2026-03-29 02:57:44.254747+00
5775dcde-7416-4d24-835f-feea9e027c7d	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	Can't find house	I'm having trouble finding your exact house. Can you provide more specific directions?	3	t	2026-03-29 02:57:44.254747+00	2026-03-29 02:57:44.254747+00
90c6a725-1895-4306-9c27-f25047c683af	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	Order delivered	Your order has been delivered. Thank you for choosing us!	4	t	2026-03-29 02:57:44.254747+00	2026-03-29 02:57:44.254747+00
1442df34-380b-412b-a432-bf6fc2ceef74	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	Running late	Sorry, I'm running a bit late due to traffic. I'll be there soon!	5	t	2026-03-29 02:57:44.254747+00	2026-03-29 02:57:44.254747+00
\.


--
-- Data for Name: rate_limit_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."rate_limit_events" ("id", "actor_id", "action", "created_at") FROM stdin;
\.


--
-- Data for Name: remittances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."remittances" ("id", "rider_id", "owner_id", "customer_name", "gallons_delivered", "empty_returned", "cash_collected", "is_credit", "credit_amount", "notes", "created_at", "is_settled", "settled_at") FROM stdin;
\.


--
-- Data for Name: reviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."reviews" ("id", "station_id", "customer_id", "order_id", "rating", "comment", "created_at") FROM stdin;
\.


--
-- Data for Name: rider_earnings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."rider_earnings" ("id", "rider_id", "order_id", "amount_earned", "is_paid_out", "created_at") FROM stdin;
\.


--
-- Data for Name: rider_locations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."rider_locations" ("id", "rider_id", "latitude", "longitude", "heading", "speed", "timestamp") FROM stdin;
efa2f51f-5f41-4c41-8ed9-ed13b382c33b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776178	125.9320966	\N	\N	2026-03-29 14:31:54.792169+00
c0319460-0c37-4d95-b98c-30da9ae376e9	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776187	125.9320946	\N	\N	2026-03-29 14:35:02.385089+00
008ad020-5f9f-4e0e-9ffb-c586fce8e880	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776185	125.9320948	\N	\N	2026-03-29 14:44:41.552339+00
d015678a-3c6c-47be-8c70-093f5cec7a90	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776184	125.9320952	\N	\N	2026-03-29 14:45:48.095837+00
4ec043d8-bf7c-4728-8db1-b6a4a528755d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776395	125.9320625	\N	\N	2026-03-29 15:03:45.318629+00
00e60e9b-1929-4198-9546-a12704baead9	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776183	125.9320954	\N	\N	2026-03-29 15:13:48.523293+00
11934de8-257b-4899-a577-fdc3236d75e0	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776216	125.93209	\N	\N	2026-03-29 15:43:09.155203+00
008a6fe5-422d-4aba-84c0-8629c2dbff5d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776371	125.9320623	\N	\N	2026-03-29 15:45:32.131567+00
7eeb75f5-8cc2-46b1-a559-467888da6651	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776193	125.9320935	\N	\N	2026-03-29 16:25:37.405534+00
6109ca92-e066-4c0c-a76d-21a341711f0c	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776192	125.9320926	\N	\N	2026-03-29 16:27:07.818947+00
06838982-818d-4fd0-8da2-d695ee77aefe	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776178	125.9320938	\N	\N	2026-03-29 16:27:33.516535+00
c1975e31-3a7e-4f3e-9b27-fc032bb71e47	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2775884	125.9320922	\N	\N	2026-05-22 14:06:51.459448+00
572c54b3-44b9-429f-8b4c-8c6986d845cd	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277629	125.9320805	\N	\N	2026-05-23 00:46:08.320405+00
4c21bed4-a0c1-4d01-a6f1-d9f49b93941e	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776302	125.9320801	\N	\N	2026-05-23 00:46:27.747562+00
c0f95283-5420-4ece-b85a-e27ea3e85481	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776311	125.9320813	\N	\N	2026-05-23 00:46:48.508941+00
0e8227d6-c57d-46ba-88a9-15593817e3f7	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776291	125.9320845	\N	\N	2026-05-23 00:47:31.427291+00
ab978fb6-7a24-4db0-b336-2469a6c641a9	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776322	125.9320832	\N	\N	2026-05-23 00:48:00.669699+00
6bdb7c61-c10b-4138-a2fc-0d80d908597b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776403	125.9320588	\N	\N	2026-05-23 00:49:12.866351+00
94cf6c84-c978-4d94-b0d1-ef611ffca6f6	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277629	125.9320805	\N	\N	2026-05-23 06:39:52.350558+00
1f398e7f-ce03-4f4b-be16-bb42e95fe76a	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277632	125.932083	\N	\N	2026-05-23 06:40:35.272897+00
6475edfb-02e0-49bd-a5fc-1bcc28995183	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776248	125.9320717	\N	\N	2026-05-27 23:57:18.336548+00
2bc95428-1274-4840-93e1-d16ac7985a58	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3371529	125.9683578	\N	\N	2026-05-28 00:42:41.493862+00
9d4c1253-de88-4c06-ab2a-04227ecbcc6a	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3371549	125.968271	\N	\N	2026-05-28 03:29:38.29333+00
9b766c49-f48f-40da-9ac7-19fede306a63	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776251	125.9320741	\N	\N	2026-05-31 02:22:26.402151+00
241d97b2-2401-4b5c-af23-d64e6f5a5dfe	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281569581651095	125.94245090729531	\N	\N	2026-05-31 02:57:37.309842+00
b28729b0-92b8-4cbb-86f1-45509688e65c	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776247	125.9320687	\N	\N	2026-05-31 02:57:44.404766+00
77154f21-6070-4da2-83f7-ff4630bd7e39	db5ff071-d21c-406a-9759-3f1c2a39903c	9.28156547219236	125.94245629470745	\N	\N	2026-05-31 02:57:49.428488+00
8a9ecb3e-9be8-4e84-ad44-c21eefcf4520	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776232	125.9320668	\N	\N	2026-05-31 02:57:57.786391+00
4acd5e1e-96a9-410e-936f-ea44743271c7	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281562135275578	125.94245572876483	\N	\N	2026-05-31 02:58:04.519671+00
007756c7-c3fc-44b1-a056-00c296b65b01	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277623	125.9320673	\N	\N	2026-05-31 02:58:10.436685+00
1bf63770-c217-45e6-8faf-ef6d223155ae	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281560552018451	125.9424523818029	\N	\N	2026-05-31 02:58:16.751511+00
ea548537-8827-4d1e-b84e-a42c001701ee	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776224	125.9320667	\N	\N	2026-05-31 02:58:23.311084+00
f3775e9d-1b3f-4713-ae39-9676b403c459	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281565116757138	125.94245212635269	\N	\N	2026-05-31 02:58:28.871026+00
4089d553-f82c-4580-8463-c8b83b423e92	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776206	125.932065	\N	\N	2026-05-31 02:58:36.611301+00
38645643-dc23-4793-bc41-c8c380dfdb89	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281568581293257	125.9424528975858	\N	\N	2026-05-31 02:58:41.522125+00
8b995a00-1a44-4aeb-b203-bfdf3b4ff629	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776286	125.9320718	\N	\N	2026-05-31 02:58:49.4778+00
78624528-a121-43af-90b5-74db91394d07	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281573570943658	125.94245699057848	\N	\N	2026-05-31 02:58:56.371788+00
81e1c4a4-7fdb-4568-b7fd-daaaa84a2ead	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776259	125.932072	\N	\N	2026-05-31 02:59:02.483204+00
3baf3bda-b725-413a-8a55-35daac2e88ba	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281577726054621	125.9424575537998	\N	\N	2026-05-31 02:59:08.613996+00
ec528e4b-9773-4fbc-b731-75ac4db24eb3	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776241	125.9320725	\N	\N	2026-05-31 02:59:15.441385+00
127777c3-d7ce-45a1-9a16-ca653d5a5f05	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281581889153793	125.94245524287028	\N	\N	2026-05-31 02:59:20.629557+00
c18efa3d-33e0-47d5-a3e2-e7ea360ad244	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776242	125.9320724	\N	\N	2026-05-31 02:59:28.43425+00
626b5850-240e-4030-a983-b02f6cf1bc10	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281583412096385	125.94245543755582	\N	\N	2026-05-31 02:59:35.961066+00
f25cc0b0-ebb3-4675-be6c-a0aa63472f6f	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776241	125.932073	\N	\N	2026-05-31 02:59:41.342737+00
48e83b0c-f654-4d4c-a7b8-756557e439dd	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281586232488909	125.94245391330104	\N	\N	2026-05-31 02:59:48.119854+00
bb3782f6-45f2-4e26-b0d1-bfb4cb3255f2	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776243	125.9320734	\N	\N	2026-05-31 02:59:54.372211+00
095db5ad-5920-464f-8a8a-7ab9af230685	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281582382797756	125.94245635570056	\N	\N	2026-05-31 03:00:00.26703+00
cf06fdfc-26f2-434f-ab29-841efc292f4a	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776245	125.9320737	\N	\N	2026-05-31 03:00:07.514664+00
65640685-c77f-4d06-bdeb-5805dfa89938	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281584375138106	125.94245007991994	\N	\N	2026-05-31 03:00:12.52908+00
e520cd2f-d30f-44be-8fed-aeae27236a92	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:00:16.00542+00
4f920dd4-3191-4a4d-bb3e-7cb58ed1ff2b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776248	125.932074	\N	\N	2026-05-31 03:00:20.369896+00
5dff23ab-6b43-4ca7-904e-834364006fad	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281589409542322	125.94244824585179	\N	\N	2026-05-31 03:00:27.684786+00
99e07b51-28c8-417f-9213-1995e6e0eba8	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776248	125.9320742	\N	\N	2026-05-31 03:00:34.389021+00
5988fcdb-41cb-4f08-8d6c-08b3f68db169	db5ff071-d21c-406a-9759-3f1c2a39903c	9.28159302640449	125.94244725708924	\N	\N	2026-05-31 03:00:40.051437+00
43ede665-5f24-434a-860a-437f9021e1e2	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776238	125.9320736	\N	\N	2026-05-31 03:00:46.462361+00
3baec2eb-999a-42d1-b5c2-1af08c1d7888	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281597915038365	125.94245230064695	\N	\N	2026-05-31 03:00:52.085959+00
7be69d8e-ea0a-4562-86a2-5f97e9ae911b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776226	125.9320744	\N	\N	2026-05-31 03:00:59.460232+00
c2831e14-32f5-4867-b6c0-c58222f1ba4d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281596894903965	125.94244856887647	\N	\N	2026-05-31 03:01:04.140229+00
d3819138-e680-4c56-84b4-468170d7b96c	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776272	125.9320736	\N	\N	2026-05-31 03:01:12.382163+00
4dac2cc4-0897-4d55-adb2-1c542d5cc089	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281590754933513	125.94244740850851	\N	\N	2026-05-31 03:01:19.411456+00
1b7bc11e-34f5-482b-8de1-d672f83ba036	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277629	125.9320725	\N	\N	2026-05-31 03:01:25.478941+00
309857c3-df15-474e-b162-cbe57bea9853	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281584306473407	125.94244795270177	\N	\N	2026-05-31 03:01:32.536118+00
cef63675-e400-4979-b413-8d40f9d744b0	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776297	125.9320715	\N	\N	2026-05-31 03:01:38.509552+00
499498c3-3a90-4d66-bdb5-f2c689e54d75	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277799333333332	125.93266683333334	\N	\N	2026-05-31 03:01:43.414697+00
ce6fa3c7-0158-43ee-8cb6-3b3aceb8512c	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281588513534455	125.94245003227577	\N	\N	2026-05-31 03:01:43.941453+00
e4e8c3f1-b65d-457b-97a0-536a19549748	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776294	125.932072	\N	\N	2026-05-31 03:01:51.501569+00
84b24f43-e127-489a-bf86-39810c9a7485	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281592220007806	125.94245405045262	\N	\N	2026-05-31 03:01:56.006273+00
6d48dcb9-c4a0-47a1-9f17-2dd53de32c30	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776296	125.9320732	\N	\N	2026-05-31 03:02:04.541767+00
c52d47a8-1f42-4f96-9ef0-fd3ba4ab63e3	db5ff071-d21c-406a-9759-3f1c2a39903c	9.281594845466044	125.94245544485887	\N	\N	2026-05-31 03:02:11.155362+00
cbf72ad0-8b62-4bbd-95e5-2916b9c9b685	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776293	125.9320734	\N	\N	2026-05-31 03:02:16.640401+00
5d691c74-c61f-448f-82ff-dc9585081b1f	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:02:20.827644+00
6bf3a3fa-98d0-495e-9064-2b640b0e6a03	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277820094044364	125.9327246282285	\N	\N	2026-05-31 03:06:30.424302+00
a701b849-2c8d-427b-a5d8-55a39959f77c	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:07:07.847787+00
383093a2-a8c4-4a82-b1f3-36f30ddbde59	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:07:57.808287+00
03ceb154-08e7-40f1-94c0-03dd257671b4	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277820094044364	125.9327246282285	\N	\N	2026-05-31 03:13:37.092921+00
3c1771fa-f895-4fea-81bd-abcfe5949e4e	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:14:25.514151+00
5d885b65-e253-466b-84c3-b63372441d14	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277799333333332	125.93266683333334	\N	\N	2026-05-31 03:15:15.850394+00
44d18108-43b8-4955-89fc-8f23445023d2	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:15:52.947775+00
3ebb356d-1553-437c-991a-36f961cd0022	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277799333333332	125.93266683333334	\N	\N	2026-05-31 03:21:04.752874+00
c534df4d-9770-45bc-915b-6b633173bb8b	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:21:41.367775+00
6aacd01b-fcac-41cf-a4b8-06e206f293ed	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:24:13.115803+00
fd13d8e2-f57e-43e9-a61d-2b50d6fb343e	de2219e9-6e80-4b21-a104-b63ae14ad08d	9.277674499999998	125.93248575	\N	\N	2026-05-31 03:24:17.497402+00
64b08e06-2180-4ada-bdac-1ef946dcf489	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776529	125.9320884	\N	\N	2026-09-24 08:19:08.941702+00
9305d095-c553-42ea-9322-f6ec2be74f0a	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776522	125.9320893	\N	\N	2026-09-24 08:26:47.856216+00
c7a9c8c9-6c0e-4f59-b2ba-cad0a7c9e32b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776399	125.9320823	\N	\N	2026-09-24 08:27:15.19126+00
63f68457-7dc1-45ff-8a86-2d1b920857cc	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776517	125.9320837	\N	\N	2026-09-24 08:28:44.365792+00
beaec8ff-9673-4265-b7b7-9f59644c03ca	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776503	125.9320839	\N	\N	2026-09-24 08:28:50.468413+00
de072739-18b6-4db1-91dc-e345497c47bc	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776522	125.9320893	\N	\N	2026-09-24 08:36:32.357733+00
ab1aaa67-8443-495c-a11c-bd3965151833	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3364599	125.9777044	\N	\N	2026-10-04 14:42:44.173277+00
8958e032-b648-44db-8575-1982b3297579	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3364367	125.9776838	\N	\N	2026-10-04 14:48:11.418703+00
0f75beaa-f1da-4ae5-bec4-3ac0bb6ddbe9	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3364545	125.9777083	\N	\N	2026-10-04 14:50:31.182649+00
54afce6b-822f-4c7c-965c-f711a3c57fa2	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3364576	125.9777068	\N	\N	2026-10-04 14:53:45.243857+00
3385eb4b-32b8-48ec-b6bc-6ecf55bbd6e8	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3364583	125.9777031	\N	\N	2026-10-06 06:04:06.787514+00
bd6f73cd-76e0-4b65-bcb8-d9b7f0b31ce5	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776518	125.9320865	\N	\N	2026-10-07 20:56:26.218852+00
2393be9a-30e4-495b-9493-d85a4bd89cac	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776505	125.9320906	\N	\N	2026-10-07 23:23:30.205447+00
5d47fb48-e576-4a17-a38a-0dc061248a19	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776524	125.9320883	\N	\N	2026-10-07 23:50:12.484036+00
bcb34489-3f71-48a4-a172-55193ce976db	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776553	125.9320823	\N	\N	2026-10-07 23:55:44.952814+00
1ed70156-f173-416f-9c04-183687d4cf35	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776522	125.9320891	\N	\N	2026-10-08 00:37:03.693787+00
82ae2944-5f07-4c21-9e50-f503fdaba177	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277652	125.9320893	\N	\N	2026-10-08 00:41:45.152476+00
4c4bc441-df50-4862-a76e-6034a8d7ebc1	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776506	125.9320933	\N	\N	2026-10-08 00:44:07.515199+00
2d5a5549-d5da-42c9-ae37-64c6c2ae3e56	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776567	125.9320857	\N	\N	2026-10-08 00:44:39.600359+00
547d680c-c942-4fa7-813e-286cab5f74c6	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776489	125.9320855	\N	\N	2026-10-08 00:44:50.581672+00
811acb43-2528-42cb-a608-4963ce8d78a8	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776547	125.9320967	\N	\N	2026-10-08 00:45:25.506318+00
aa652397-7ad3-4a11-9f6a-af3f036d2cbe	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776554	125.9320905	\N	\N	2026-10-08 01:12:06.900047+00
116056a7-e237-4102-93b6-cc867b26b17f	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776258	125.9320994	\N	\N	2026-10-08 01:12:29.290025+00
3f366740-f494-4057-b66b-136f315fb5d6	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776192	125.9321003	\N	\N	2026-10-08 01:12:42.416614+00
1d2f16f3-f7dd-4d02-be32-8ef7aa7b7d98	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776386	125.9320966	\N	\N	2026-10-08 01:13:09.158132+00
506a0ae7-1403-4529-bea7-90a6926cd930	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776432	125.932092	\N	\N	2026-10-08 01:14:07.290624+00
35efdbbf-3456-47f3-9f1b-b58b0f86ab5d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277641	125.9320858	\N	\N	2026-10-08 01:19:56.614715+00
2b387019-0c84-4625-a7af-f2214fdf49aa	db5ff071-d21c-406a-9759-3f1c2a39903c	9.277643	125.9320851	\N	\N	2026-10-08 01:20:09.11899+00
7343d61c-3a1c-44b7-b86d-ae90558d0cb0	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776463	125.9320733	\N	\N	2026-10-08 10:56:05.290352+00
aa68a6c5-4f85-4a9d-ba45-226e1b330be0	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776494	125.932066	\N	\N	2026-10-08 10:56:26.835064+00
5a790666-e181-41ee-948f-7d683f2de92b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776507	125.9320659	\N	\N	2026-10-08 11:01:51.573198+00
8f831da5-7cab-4200-abbd-4ba39698010b	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776444	125.9320644	\N	\N	2026-10-08 11:08:42.176555+00
2b166900-1354-4262-b1c3-0aa6c1390b8d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776422	125.9320672	\N	\N	2026-10-08 11:08:48.434195+00
130f6f0c-3cdd-44ad-b0fa-a6994abd6872	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776524	125.9320886	\N	\N	2026-10-08 11:12:57.728764+00
9a66bff0-df91-45af-a624-8d03e3c5115d	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776524	125.9320886	\N	\N	2026-10-08 13:48:50.432026+00
1ef183a9-c253-47ef-bf9e-0f1024e79f15	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776524	125.9320883	\N	\N	2026-10-08 13:50:02.975848+00
c6fb52cb-6457-4097-8ce7-060725283cb5	db5ff071-d21c-406a-9759-3f1c2a39903c	9.2776523	125.9320888	\N	\N	2026-10-08 13:53:34.006843+00
2f31ce3e-1954-4d06-a42a-6c90e32abbb5	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3390552	125.9725518	\N	\N	2026-10-09 01:02:29.543569+00
36417584-2264-4b0c-9836-521cb1dfdfd6	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3390534	125.9725551	\N	\N	2026-10-09 01:03:15.430305+00
9ec7217c-743f-4359-86c6-8baa213eb967	db5ff071-d21c-406a-9759-3f1c2a39903c	9.3390565	125.9725556	\N	\N	2026-10-09 01:03:43.520123+00
\.


--
-- Data for Name: subscriptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."subscriptions" ("id", "customer_id", "owner_id", "product_id", "quantity", "frequency", "delivery_days", "next_delivery_date", "is_active", "created_at") FROM stdin;
\.


--
-- Data for Name: suspicious_activities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."suspicious_activities" ("id", "rider_id", "order_id", "activity_type", "severity", "details", "created_at") FROM stdin;
\.


--
-- Data for Name: system_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."system_config" ("id", "key", "value", "description", "updated_at") FROM stdin;
c9bfa7d9-8d37-4718-b6b3-25561686f8d9	min_app_version	"1.0.0"	Minimum version required for operational safety	2026-03-29 04:35:00.016545+00
2ed11387-fd0d-4ec0-b38c-683bf6928476	api_version	"v1"	Current supported stable API version	2026-03-29 04:35:00.016545+00
4007a0ca-11b7-47d3-997d-0ed7dbf19fee	feature_smart_dispatch_enabled	true	Master toggle for automated rider assignment	2026-03-29 04:35:00.016545+00
d8771279-0f5f-48e2-a061-556645bffb8f	feature_gcash_enabled	true	Master toggle for digital payments	2026-05-29 10:51:27.346895+00
e25e31a1-14f1-4e7d-bc2c-184f40861e8e	platform_fee_enabled	true	When true, a platform fee is added to every completed checkout	2026-10-08 07:59:53.510044+00
c907d4e1-668c-4bae-b01c-733fb8eb0c0b	platform_fee_percent	0.00	Platform fee percentage applied to subtotal + delivery (e.g. 2.5 = 2.5%)	2026-10-08 07:59:53.510044+00
7e9b49cc-3102-498c-9358-df6e4e6f5b99	platform_fee_fixed	0.50	Flat platform fee in PHP added on top of the percentage fee	2026-10-08 07:59:53.510044+00
4e6f195f-fb96-48f1-aa80-d63f080df4b2	maintenance_mode	false	Global lockout for system updates	2026-10-08 08:00:28.420921+00
\.


--
-- Data for Name: system_notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY "public"."system_notifications" ("id", "user_id", "type", "priority", "title", "content", "metadata", "is_read", "read_at", "action_url", "created_at", "expires_at") FROM stdin;
262b56dd-a9c4-42f1-85fa-7ed99ecc084c	de2219e9-6e80-4b21-a104-b63ae14ad08d	order_assigned	high	New Order Assigned!	You have been assigned a new order from Jherald Kim Aspillaga for ₱150.00	{"order_id": "2cbe9448-73fa-4945-b142-4beb717e3939", "total_amount": 150.00, "customer_name": "Jherald Kim Aspillaga", "delivery_address": null}	f	\N	\N	2026-03-23 04:59:06.570999+00	\N
80eb4f2c-c830-4546-a2de-194928d2f4ba	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	station_broadcast	normal	Station Alert	way pasok kuman	{}	f	\N	\N	2026-03-29 12:10:38.73516+00	\N
3c213ab5-c3f2-4250-95df-a206bc20f3fe	aece23c3-1302-431d-aeea-a6b7fe0bd9a0	order_assigned	high	New Order Assigned!	You have been assigned a new order from Vilma C Aspillaga  for ₱75.00	{"order_id": "3afe4ca4-2432-4d31-9b1b-e3d249bbd69c", "total_amount": 75.00, "customer_name": "Vilma C Aspillaga ", "delivery_address": "Purok 11, Parang, Cantilan, Surigao Del Sur"}	f	\N	\N	2026-03-29 12:10:54.753492+00	\N
37632619-d8a7-49c6-943a-761a48d51080	de2219e9-6e80-4b21-a104-b63ae14ad08d	station_broadcast	normal	Station Alert	way pasok kuman	{}	f	\N	\N	2026-05-23 06:39:23.565704+00	\N
e3e62ff9-480c-4c42-9eea-54646aff6d5f	db5ff071-d21c-406a-9759-3f1c2a39903c	station_broadcast	normal	Station Alert	way pasok kuman	{}	t	2026-05-23 14:39:56.717974+00	\N	2026-05-23 06:39:23.565704+00	\N
576b2cd1-e51e-47ae-afa0-c731299e98be	681eee4f-a7b6-46ab-87de-6965c92c5711	order_assigned	high	Rider Assigned to Refill	Jaylord Buiza has been assigned to deliver your water refill.	{"order_id": "c887f19c-2f1d-4ce5-b870-2945c46b0698", "rider_id": "db5ff071-d21c-406a-9759-3f1c2a39903c", "rider_name": "Jaylord Buiza"}	t	2026-10-09 08:56:53.206403+00	\N	2026-10-08 10:55:18.982674+00	\N
86869fd5-8d07-4b45-a62c-9516cf8d9142	db5ff071-d21c-406a-9759-3f1c2a39903c	order_assigned	high	New Order Assigned!	You have been assigned a new order from Jherald Kim G Aspillaga  for ₱45.00	{"order_id": "702f471e-392a-47dd-a992-ab262738f20f", "total_amount": 45.00, "customer_name": "Jherald Kim G Aspillaga ", "delivery_address": "Purok 11, Parang, Cantilan, Surigao Del Sur"}	t	2026-05-23 14:40:22.3147+00	\N	2026-04-09 03:29:45.510743+00	\N
6337778b-bf5b-43b4-9f5d-f6e493f2165a	de2219e9-6e80-4b21-a104-b63ae14ad08d	station_broadcast	normal	Station Alert	way duty	{}	f	\N	\N	2026-09-23 12:22:41.752949+00	\N
9145a7c9-89ff-42ce-bceb-37279576ce79	db5ff071-d21c-406a-9759-3f1c2a39903c	order_assigned	high	New Order Assigned!	You have been assigned a new order from Jherald Kim Aspillaga for ₱90.00	{"order_id": "ed89a831-bc93-4c97-96bc-e7fcf68cf639", "total_amount": 90.00, "customer_name": "Jherald Kim Aspillaga", "delivery_address": "Purok 11, Parang, Cantilan, Surigao Del Sur"}	t	2026-03-30 00:25:47.750202+00	\N	2026-03-23 13:39:15.459612+00	\N
13800383-e466-4841-8ef5-a1d40c97404b	de2219e9-6e80-4b21-a104-b63ae14ad08d	station_broadcast	normal	Station Alert	hello	{}	f	\N	\N	2026-09-24 08:26:15.016209+00	\N
856a6013-e354-4e9b-9b41-05852f7f57f2	db5ff071-d21c-406a-9759-3f1c2a39903c	station_broadcast	normal	Station Alert	way duty	{}	t	2026-10-04 22:51:55.713326+00	\N	2026-09-23 12:22:41.752949+00	\N
e6aafdaf-d686-4060-a58e-bf266ba0f6fb	db5ff071-d21c-406a-9759-3f1c2a39903c	station_broadcast	normal	Station Alert	hello	{}	t	2026-10-08 07:23:42.905509+00	\N	2026-09-24 08:26:15.016209+00	\N
e8518aaa-d2c7-4227-9a4e-f9d8c41d2ca9	db5ff071-d21c-406a-9759-3f1c2a39903c	order_assigned	high	New Order Assigned!	You have been assigned a new order from Jherald Kim G Aspillaga  for ₱45.00	{"order_id": "4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4", "total_amount": 45.00, "customer_name": "Jherald Kim G Aspillaga ", "delivery_address": "Purok 11, Parang, Cantilan, Surigao Del Sur"}	t	2026-10-08 07:24:49.44186+00	\N	2026-03-29 14:19:21.789889+00	\N
8a1de5d5-26e8-474e-95b0-53e35dc07177	681eee4f-a7b6-46ab-87de-6965c92c5711	order_cancelled	high	Order cancelled		{"order_id": "702f471e-392a-47dd-a992-ab262738f20f"}	t	2026-10-08 18:43:20.322131+00	\N	2026-10-08 04:25:33.1119+00	\N
e7cdd47f-3a0d-47c7-a1ac-ba8f11ea72d3	db5ff071-d21c-406a-9759-3f1c2a39903c	order_assigned	high	New Order Assigned!	You have been assigned a new order from Jherald Kim G. Aspillaga for ₱45.50	{"order_id": "c887f19c-2f1d-4ce5-b870-2945c46b0698", "total_amount": 45.50, "customer_name": "Jherald Kim G. Aspillaga", "delivery_address": "Purok 11, Parang, Cantilan, Surigao Del Sur, Parang, Cantilan, 8317"}	f	\N	\N	2026-10-08 10:55:18.982674+00	\N
e64c2436-105a-4a64-b621-1f73d7abf295	db5ff071-d21c-406a-9759-3f1c2a39903c	order_assigned	urgent	New Delivery Assignment	You have been assigned order #C887F19C for Jherald Kim G. Aspillaga.	{"status": "assigned_to_rider", "order_id": "c887f19c-2f1d-4ce5-b870-2945c46b0698"}	f	\N	\N	2026-10-08 10:55:18.982674+00	\N
\.


--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."buckets" ("id", "name", "owner", "created_at", "updated_at", "public", "avif_autodetection", "file_size_limit", "allowed_mime_types", "owner_id", "type", "versioning_status", "lifecycle_configuration", "lifecycle_configuration_generation") FROM stdin;
product_images	product_images	\N	2026-03-18 14:56:09.433383+00	2026-03-18 14:56:09.433383+00	t	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
avatars	avatars	\N	2026-03-28 06:47:48.099717+00	2026-03-28 06:47:48.099717+00	t	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
chat_attachments	chat_attachments	\N	2026-03-18 11:06:44.780889+00	2026-03-18 11:06:44.780889+00	f	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
delivery_proofs	delivery_proofs	\N	2026-03-29 04:16:20.872659+00	2026-03-29 04:16:20.872659+00	f	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
payment_proofs	payment_proofs	\N	2026-05-22 15:08:19.386441+00	2026-05-22 15:08:19.386441+00	f	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
\.


--
-- Data for Name: buckets_analytics; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."buckets_analytics" ("name", "type", "format", "created_at", "updated_at", "id", "deleted_at") FROM stdin;
\.


--
-- Data for Name: buckets_vectors; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."buckets_vectors" ("id", "type", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."objects" ("id", "bucket_id", "name", "owner", "created_at", "updated_at", "last_accessed_at", "metadata", "version", "owner_id", "user_metadata", "archived_at", "is_delete_marker", "is_versioned") FROM stdin;
fdf5c23d-204e-4fc7-a2e9-b9c58e8778be	delivery_proofs	proofs/702f471e-392a-47dd-a992-ab262738f20f/702f471e-392a-47dd-a992-ab262738f20f_1791420325189.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 00:45:25.745567+00	2026-10-08 00:45:25.745567+00	2026-10-08 00:45:25.745567+00	{"eTag": "\\"6dde9dcb2f63373f17290e6a47ba6c35\\"", "size": 42829, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T00:45:26.000Z", "contentLength": 42829, "httpStatusCode": 200}	1e5b7836-1bf7-46ee-b809-4ddc4bbb2a74	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
215b5910-f066-4ab2-a80e-3584c5d38f67	avatars	669cfc05-4701-4332-b604-71cdc2a56679.jpg	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-28 06:48:59.862003+00	2026-03-28 06:50:47.590093+00	2026-03-28 06:48:59.862003+00	{"eTag": "\\"85a2978fb0199535dfe19e344fe8f764\\"", "size": 102106, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-03-28T06:50:48.000Z", "contentLength": 102106, "httpStatusCode": 200}	e8841340-9d4f-498c-a7f1-6f8a36c8ce16	669cfc05-4701-4332-b604-71cdc2a56679	{}	\N	f	f
66a86b6f-d5de-4945-bcc6-28da56bfa339	avatars	cover_c341c225-308e-4ff6-84bb-0f1e8732e3b8.jpg	c341c225-308e-4ff6-84bb-0f1e8732e3b8	2026-03-29 02:52:56.330717+00	2026-03-29 02:52:56.330717+00	2026-03-29 02:52:56.330717+00	{"eTag": "\\"c41d146a709b1cec3c24783e02416db7\\"", "size": 129622, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-03-29T02:52:57.000Z", "contentLength": 129622, "httpStatusCode": 200}	269e386b-45de-41a6-86f2-a2343ecd862c	c341c225-308e-4ff6-84bb-0f1e8732e3b8	{}	\N	f	f
8367985e-ee7b-433b-a827-d64ee0c1164a	avatars	avatar_c341c225-308e-4ff6-84bb-0f1e8732e3b8.png	c341c225-308e-4ff6-84bb-0f1e8732e3b8	2026-03-29 02:53:02.501261+00	2026-03-29 02:53:02.501261+00	2026-03-29 02:53:02.501261+00	{"eTag": "\\"bb332fa7b8b9a321d334c71cc258ea08\\"", "size": 65597, "mimetype": "image/png", "cacheControl": "max-age=3600", "lastModified": "2026-03-29T02:53:03.000Z", "contentLength": 65597, "httpStatusCode": 200}	417f168f-313a-40ae-b675-65373b6f9daa	c341c225-308e-4ff6-84bb-0f1e8732e3b8	{}	\N	f	f
64d93681-0106-4a63-9e16-2cedb19b66b4	avatars	avatar_db5ff071-d21c-406a-9759-3f1c2a39903c.png	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-03-29 16:27:33.34018+00	2026-03-29 16:27:33.34018+00	2026-03-29 16:27:33.34018+00	{"eTag": "\\"49a495bee26af52f8f42ff9513daa70b\\"", "size": 41345, "mimetype": "image/png", "cacheControl": "max-age=3600", "lastModified": "2026-03-29T16:27:34.000Z", "contentLength": 41345, "httpStatusCode": 200}	34ca2b4e-8c58-42f4-b0eb-e507026213d0	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
eb5424d7-6a0b-40d1-bbf5-3961f25255d1	delivery_proofs	proofs/702f471e-392a-47dd-a992-ab262738f20f/702f471e-392a-47dd-a992-ab262738f20f_1779497204066.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-05-23 00:46:46.622199+00	2026-05-23 00:46:46.622199+00	2026-05-23 00:46:46.622199+00	{"eTag": "\\"f71a149b4048394350ca51b33f9b4993\\"", "size": 57366, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-05-23T00:46:47.000Z", "contentLength": 57366, "httpStatusCode": 200}	b98c5f21-6092-47f3-842b-4ce5ec65318a	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
3942006b-ae31-439d-8da0-29eb7212a25f	avatars	avatar_669cfc05-4701-4332-b604-71cdc2a56679.jpg	669cfc05-4701-4332-b604-71cdc2a56679	2026-10-06 03:20:25.025228+00	2026-10-06 03:20:25.025228+00	2026-10-06 03:20:25.025228+00	{"eTag": "\\"448dcee5339defcb3d435aaf9f747c7b\\"", "size": 78995, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-06T03:20:26.000Z", "contentLength": 78995, "httpStatusCode": 200}	21c6a9ad-a307-4d5d-8b63-6c2a59100075	669cfc05-4701-4332-b604-71cdc2a56679	{}	\N	f	f
a1c3e4d3-31cf-481b-b58d-eab4831ab80b	delivery_proofs	proofs/702f471e-392a-47dd-a992-ab262738f20f/702f471e-392a-47dd-a992-ab262738f20f_1791421946013.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 01:12:26.806175+00	2026-10-08 01:12:26.806175+00	2026-10-08 01:12:26.806175+00	{"eTag": "\\"0501de7cc541631a1d897bd08c20a0c4\\"", "size": 42271, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T01:12:27.000Z", "contentLength": 42271, "httpStatusCode": 200}	30e2ad91-3cd2-4f5f-9038-f0290b0b0b8f	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
efab0ccb-f6cf-429a-af98-a39fbc117c0d	delivery_proofs	proofs/702f471e-392a-47dd-a992-ab262738f20f/702f471e-392a-47dd-a992-ab262738f20f_1791422408881.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 01:20:09.412658+00	2026-10-08 01:20:09.412658+00	2026-10-08 01:20:09.412658+00	{"eTag": "\\"904f8d308837cfe878568db692c869f3\\"", "size": 51816, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T01:20:10.000Z", "contentLength": 51816, "httpStatusCode": 200}	89db779a-088d-4f0d-b77a-fa4345bd2112	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
98bcbc2a-524d-4f26-8028-62aa16485485	avatars	cover_669cfc05-4701-4332-b604-71cdc2a56679.jpg	669cfc05-4701-4332-b604-71cdc2a56679	2026-03-28 08:29:12.892178+00	2026-10-08 01:28:59.969588+00	2026-03-28 08:29:12.892178+00	{"eTag": "\\"39f20462ecde7a302b0fff37c2193f3d\\"", "size": 68508, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T01:29:00.000Z", "contentLength": 68508, "httpStatusCode": 200}	ee79ce4f-0b07-47fe-9328-1ce09905873f	669cfc05-4701-4332-b604-71cdc2a56679	{}	\N	f	f
50402fc5-d179-4c6f-8602-8b94e7f528a2	delivery_proofs	proofs/4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4/4b2e79c2-b3b7-4206-ac41-eaa8e82c23b4_1791456986450.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 10:56:26.976006+00	2026-10-08 10:56:26.976006+00	2026-10-08 10:56:26.976006+00	{"eTag": "\\"9fa1ce181041781b4956fedf24d1974e\\"", "size": 34850, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T10:56:27.000Z", "contentLength": 34850, "httpStatusCode": 200}	ee876177-db51-42e6-9b87-53912614ea10	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
8512da70-5396-4b95-bba1-4e55ad61a710	delivery_proofs	proofs/c887f19c-2f1d-4ce5-b870-2945c46b0698/c887f19c-2f1d-4ce5-b870-2945c46b0698_1791467613511.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-08 13:53:35.724074+00	2026-10-08 13:53:35.724074+00	2026-10-08 13:53:35.724074+00	{"eTag": "\\"64573a49ef4d4d4c382a76da5b2e1b8a\\"", "size": 114272, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-08T13:53:36.000Z", "contentLength": 114272, "httpStatusCode": 200}	4ce27d0d-a4e9-4b6f-af64-40e03cf2346e	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
941a2146-1f30-428a-943b-67d7164233ab	delivery_proofs	proofs/c887f19c-2f1d-4ce5-b870-2945c46b0698/c887f19c-2f1d-4ce5-b870-2945c46b0698_1791507794037.jpg	db5ff071-d21c-406a-9759-3f1c2a39903c	2026-10-09 01:03:15.120502+00	2026-10-09 01:03:15.120502+00	2026-10-09 01:03:15.120502+00	{"eTag": "\\"e172f62bfa1cff11289cb086011e6c9f\\"", "size": 61130, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-10-09T01:03:16.000Z", "contentLength": 61130, "httpStatusCode": 200}	62126fe2-e41d-4927-9104-e2b12c270af5	db5ff071-d21c-406a-9759-3f1c2a39903c	{}	\N	f	f
\.


--
-- Data for Name: s3_multipart_uploads; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."s3_multipart_uploads" ("id", "in_progress_size", "upload_signature", "bucket_id", "key", "version", "owner_id", "created_at", "user_metadata", "metadata") FROM stdin;
\.


--
-- Data for Name: s3_multipart_uploads_parts; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."s3_multipart_uploads_parts" ("id", "upload_id", "size", "part_number", "bucket_id", "key", "etag", "owner_id", "version", "created_at") FROM stdin;
\.


--
-- Data for Name: vector_indexes; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--

COPY "storage"."vector_indexes" ("id", "name", "bucket_id", "data_type", "dimension", "distance_metric", "metadata_configuration", "created_at", "updated_at") FROM stdin;
\.


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: auth; Owner: supabase_auth_admin
--

SELECT pg_catalog.setval('"auth"."refresh_tokens_id_seq"', 459, true);


--
-- PostgreSQL database dump complete
--

-- \unrestrict tCz5WOU0mcOqu2sD7bUcyy9Tl9HZuLdFbr7RVIz6KAANIjalMbl30tCxOYhJp2H

RESET ALL;
