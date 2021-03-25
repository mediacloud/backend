--
-- PostgreSQL database dump
--

-- Dumped from database version 11.11 (Ubuntu 11.11-1.pgdg20.04+1)
-- Dumped by pg_dump version 11.11 (Ubuntu 11.11-1.pgdg20.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: executions_visibility; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.executions_visibility (
    namespace_id character(64) NOT NULL,
    run_id character(64) NOT NULL,
    start_time timestamp without time zone NOT NULL,
    execution_time timestamp without time zone NOT NULL,
    workflow_id character varying(255) NOT NULL,
    workflow_type_name character varying(255) NOT NULL,
    status integer NOT NULL,
    close_time timestamp without time zone,
    history_length bigint,
    memo bytea,
    encoding character varying(64) NOT NULL,
    task_queue character varying(255) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.executions_visibility OWNER TO temporal;

--
-- Name: schema_update_history; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.schema_update_history (
    version_partition integer NOT NULL,
    year integer NOT NULL,
    month integer NOT NULL,
    update_time timestamp without time zone NOT NULL,
    description character varying(255),
    manifest_md5 character varying(64),
    new_version character varying(64),
    old_version character varying(64)
);


ALTER TABLE public.schema_update_history OWNER TO temporal;

--
-- Name: schema_version; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.schema_version (
    version_partition integer NOT NULL,
    db_name character varying(255) NOT NULL,
    creation_time timestamp without time zone,
    curr_version character varying(64),
    min_compatible_version character varying(64)
);


ALTER TABLE public.schema_version OWNER TO temporal;

--
-- Data for Name: executions_visibility; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.executions_visibility (namespace_id, run_id, start_time, execution_time, workflow_id, workflow_type_name, status, close_time, history_length, memo, encoding, task_queue) FROM stdin;
\.


--
-- Data for Name: schema_update_history; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.schema_update_history (version_partition, year, month, update_time, description, manifest_md5, new_version, old_version) FROM stdin;
0	2021	3	2021-03-21 23:09:18.317158	initial version		0.0	0
0	2021	3	2021-03-21 23:09:18.40721	base version of visibility schema	698373883c1c0dd44607a446a62f2a79	1.0	0.0
0	2021	3	2021-03-21 23:09:18.41287	add close time & status index	e286f8af0a62e291b35189ce29d3fff3	1.1	1.0
\.


--
-- Data for Name: schema_version; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.schema_version (version_partition, db_name, creation_time, curr_version, min_compatible_version) FROM stdin;
0	temporal_visibility	2021-03-21 23:09:18.411815	1.1	0.1
\.


--
-- Name: executions_visibility executions_visibility_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.executions_visibility
    ADD CONSTRAINT executions_visibility_pkey PRIMARY KEY (namespace_id, run_id);


--
-- Name: schema_update_history schema_update_history_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.schema_update_history
    ADD CONSTRAINT schema_update_history_pkey PRIMARY KEY (version_partition, year, month, update_time);


--
-- Name: schema_version schema_version_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_pkey PRIMARY KEY (version_partition, db_name);


--
-- Name: by_close_time_by_status; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_close_time_by_status ON public.executions_visibility USING btree (namespace_id, close_time DESC, run_id, status);


--
-- Name: by_status_by_close_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_status_by_close_time ON public.executions_visibility USING btree (namespace_id, status, close_time DESC, run_id);


--
-- Name: by_status_by_start_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_status_by_start_time ON public.executions_visibility USING btree (namespace_id, status, start_time DESC, run_id);


--
-- Name: by_type_close_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_type_close_time ON public.executions_visibility USING btree (namespace_id, workflow_type_name, status, close_time DESC, run_id);


--
-- Name: by_type_start_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_type_start_time ON public.executions_visibility USING btree (namespace_id, workflow_type_name, status, start_time DESC, run_id);


--
-- Name: by_workflow_id_close_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_workflow_id_close_time ON public.executions_visibility USING btree (namespace_id, workflow_id, status, close_time DESC, run_id);


--
-- Name: by_workflow_id_start_time; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX by_workflow_id_start_time ON public.executions_visibility USING btree (namespace_id, workflow_id, status, start_time DESC, run_id);


--
-- PostgreSQL database dump complete
--
