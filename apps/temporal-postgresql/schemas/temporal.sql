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
-- Name: activity_info_maps; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.activity_info_maps (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    schedule_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16)
);


ALTER TABLE public.activity_info_maps OWNER TO temporal;

--
-- Name: buffered_events; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.buffered_events (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.buffered_events OWNER TO temporal;

--
-- Name: buffered_events_id_seq; Type: SEQUENCE; Schema: public; Owner: temporal
--

CREATE SEQUENCE public.buffered_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.buffered_events_id_seq OWNER TO temporal;

--
-- Name: buffered_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: temporal
--

ALTER SEQUENCE public.buffered_events_id_seq OWNED BY public.buffered_events.id;


--
-- Name: child_execution_info_maps; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.child_execution_info_maps (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    initiated_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16)
);


ALTER TABLE public.child_execution_info_maps OWNER TO temporal;

--
-- Name: cluster_membership; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.cluster_membership (
    membership_partition integer NOT NULL,
    host_id bytea NOT NULL,
    rpc_address character varying(15) NOT NULL,
    rpc_port smallint NOT NULL,
    role smallint NOT NULL,
    session_start timestamp without time zone DEFAULT '1970-01-01 00:00:01'::timestamp without time zone,
    last_heartbeat timestamp without time zone DEFAULT '1970-01-01 00:00:01'::timestamp without time zone,
    record_expiry timestamp without time zone DEFAULT '1970-01-01 00:00:01'::timestamp without time zone
);


ALTER TABLE public.cluster_membership OWNER TO temporal;

--
-- Name: cluster_metadata; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.cluster_metadata (
    metadata_partition integer NOT NULL,
    data bytea DEFAULT '\x'::bytea NOT NULL,
    data_encoding character varying(16) DEFAULT 'Proto3'::character varying NOT NULL,
    version bigint DEFAULT 1 NOT NULL
);


ALTER TABLE public.cluster_metadata OWNER TO temporal;

--
-- Name: current_executions; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.current_executions (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    create_request_id character varying(64) NOT NULL,
    state integer NOT NULL,
    status integer NOT NULL,
    start_version bigint NOT NULL,
    last_write_version bigint NOT NULL
);


ALTER TABLE public.current_executions OWNER TO temporal;

--
-- Name: executions; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.executions (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    next_event_id bigint NOT NULL,
    last_write_version bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL,
    state bytea NOT NULL,
    state_encoding character varying(16) NOT NULL
);


ALTER TABLE public.executions OWNER TO temporal;

--
-- Name: history_node; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.history_node (
    shard_id integer NOT NULL,
    tree_id bytea NOT NULL,
    branch_id bytea NOT NULL,
    node_id bigint NOT NULL,
    txn_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.history_node OWNER TO temporal;

--
-- Name: history_tree; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.history_tree (
    shard_id integer NOT NULL,
    tree_id bytea NOT NULL,
    branch_id bytea NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.history_tree OWNER TO temporal;

--
-- Name: namespace_metadata; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.namespace_metadata (
    partition_id integer NOT NULL,
    notification_version bigint NOT NULL
);


ALTER TABLE public.namespace_metadata OWNER TO temporal;

--
-- Name: namespaces; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.namespaces (
    partition_id integer NOT NULL,
    id bytea NOT NULL,
    name character varying(255) NOT NULL,
    notification_version bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL,
    is_global boolean NOT NULL
);


ALTER TABLE public.namespaces OWNER TO temporal;

--
-- Name: queue; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.queue (
    queue_type integer NOT NULL,
    message_id bigint NOT NULL,
    message_payload bytea NOT NULL,
    message_encoding character varying(16) DEFAULT 'Json'::character varying NOT NULL
);


ALTER TABLE public.queue OWNER TO temporal;

--
-- Name: queue_metadata; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.queue_metadata (
    queue_type integer NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) DEFAULT 'Json'::character varying NOT NULL
);


ALTER TABLE public.queue_metadata OWNER TO temporal;

--
-- Name: replication_tasks; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.replication_tasks (
    shard_id integer NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.replication_tasks OWNER TO temporal;

--
-- Name: replication_tasks_dlq; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.replication_tasks_dlq (
    source_cluster_name character varying(255) NOT NULL,
    shard_id integer NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.replication_tasks_dlq OWNER TO temporal;

--
-- Name: request_cancel_info_maps; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.request_cancel_info_maps (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    initiated_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16)
);


ALTER TABLE public.request_cancel_info_maps OWNER TO temporal;

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
-- Name: shards; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.shards (
    shard_id integer NOT NULL,
    range_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.shards OWNER TO temporal;

--
-- Name: signal_info_maps; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.signal_info_maps (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    initiated_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16)
);


ALTER TABLE public.signal_info_maps OWNER TO temporal;

--
-- Name: signals_requested_sets; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.signals_requested_sets (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    signal_id character varying(64) NOT NULL
);


ALTER TABLE public.signals_requested_sets OWNER TO temporal;

--
-- Name: task_queues; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.task_queues (
    range_hash bigint NOT NULL,
    task_queue_id bytea NOT NULL,
    range_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.task_queues OWNER TO temporal;

--
-- Name: tasks; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.tasks (
    range_hash bigint NOT NULL,
    task_queue_id bytea NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.tasks OWNER TO temporal;

--
-- Name: timer_info_maps; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.timer_info_maps (
    shard_id integer NOT NULL,
    namespace_id bytea NOT NULL,
    workflow_id character varying(255) NOT NULL,
    run_id bytea NOT NULL,
    timer_id character varying(255) NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16)
);


ALTER TABLE public.timer_info_maps OWNER TO temporal;

--
-- Name: timer_tasks; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.timer_tasks (
    shard_id integer NOT NULL,
    visibility_timestamp timestamp without time zone NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.timer_tasks OWNER TO temporal;

--
-- Name: transfer_tasks; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.transfer_tasks (
    shard_id integer NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.transfer_tasks OWNER TO temporal;

--
-- Name: visibility_tasks; Type: TABLE; Schema: public; Owner: temporal
--

CREATE TABLE public.visibility_tasks (
    shard_id integer NOT NULL,
    task_id bigint NOT NULL,
    data bytea NOT NULL,
    data_encoding character varying(16) NOT NULL
);


ALTER TABLE public.visibility_tasks OWNER TO temporal;

--
-- Name: buffered_events id; Type: DEFAULT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.buffered_events ALTER COLUMN id SET DEFAULT nextval('public.buffered_events_id_seq'::regclass);


--
-- Data for Name: activity_info_maps; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.activity_info_maps (shard_id, namespace_id, workflow_id, run_id, schedule_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: buffered_events; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.buffered_events (shard_id, namespace_id, workflow_id, run_id, id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: child_execution_info_maps; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.child_execution_info_maps (shard_id, namespace_id, workflow_id, run_id, initiated_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: cluster_membership; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.cluster_membership (membership_partition, host_id, rpc_address, rpc_port, role, session_start, last_heartbeat, record_expiry) FROM stdin;
0	\\xd343f2848d9b11eba18c02420a010005	10.1.0.5	6933	1	2021-03-25 18:56:36.884362	2021-03-25 18:57:25.896779	2021-03-27 18:57:25.896779
0	\\xd346e1178d9b11eba18c02420a010005	10.1.0.5	6935	3	2021-03-25 18:56:36.908823	2021-03-25 18:57:28.931428	2021-03-27 18:57:28.931428
0	\\xd34bfa858d9b11eba18c02420a010005	10.1.0.5	6939	4	2021-03-25 18:56:36.936065	2021-03-25 18:57:36.950967	2021-03-27 18:57:36.950967
0	\\xd3454ab18d9b11eba18c02420a010005	10.1.0.5	6934	2	2021-03-25 18:56:36.892785	2021-03-25 18:57:38.910999	2021-03-27 18:57:38.910999
\.


--
-- Data for Name: cluster_metadata; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.cluster_metadata (metadata_partition, data, data_encoding, version) FROM stdin;
0	\\x0a0661637469766510101a2432323465333031362d636566362d343963642d393565302d663962656330306438653934	Proto3	1
\.


--
-- Data for Name: current_executions; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.current_executions (shard_id, namespace_id, workflow_id, run_id, create_request_id, state, status, start_version, last_write_version) FROM stdin;
8	\\x32049b68787240948e63d0dd59896a83	temporal-sys-tq-scanner	\\x8b5622d072f44c068c5e4b04d4b3a410	766425e5-f5f5-4743-ba90-8ca7ebdcdfb7	1	10	0
\.


--
-- Data for Name: executions; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.executions (shard_id, namespace_id, workflow_id, run_id, next_event_id, last_write_version, data, data_encoding, state, state_encoding) FROM stdin;
8	\\x32049b68787240948e63d0dd59896a83	temporal-sys-tq-scanner	\\x8b5622d072f44c068c5e4b04d4b3a410	2	0	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121774656d706f72616c2d7379732d74712d7363616e6e65724a2374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d30522074656d706f72616c2d7379732d74712d7363616e6e65722d776f726b666c6f775a0062040880af1a6a02080a8801808040900101a2010c08e8b9f3820610ebfaefc803aa010c08e8b9f3820610ebfaefc803ca0100d00101fa0109656d70747955756964980201da020c30202a2f3132202a202a202ab2035412520a4c0a2438623536323264302d373266342d346330362d386335652d346230346434623361343130122438633465363161342d386136312d346263372d613234362d32373039363532303138326212020801ba032438623536323264302d373266342d346330362d386335652d346230346434623361343130c2030308f201ca030c0880f78e830610ebfaefc803	Proto3	\\x0a2437363634323565352d663566352d343734332d626139302d386361376562646364666237122438623536323264302d373266342d346330362d386335652d34623034643462336134313018012001	Proto3
\.


--
-- Data for Name: history_node; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.history_node (shard_id, tree_id, branch_id, node_id, txn_id, data, data_encoding) FROM stdin;
8	\\x8b5622d072f44c068c5e4b04d4b3a410	\\x8c4e61a48a614bc7a24627096520182b	1	-1048577	\\x0aef010801120c08e8b9f3820610ebfaefc80318012880804032d6010a220a2074656d706f72616c2d7379732d74712d7363616e6e65722d776f726b666c6f772a270a2374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d3010013a0042040880af1a4a02080a5803722438623536323264302d373266342d346330362d386335652d3462303464346233613431307a103435406561346434626234623434314082012438623536323264302d373266342d346330362d386335652d346230346434623361343130900101a2010c30202a2f3132202a202a202aaa010408988e01ca0100	Proto3
\.


--
-- Data for Name: history_tree; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.history_tree (shard_id, tree_id, branch_id, data, data_encoding) FROM stdin;
8	\\x8b5622d072f44c068c5e4b04d4b3a410	\\x8c4e61a48a614bc7a24627096520182b	\\x0a4c0a2438623536323264302d373266342d346330362d386335652d346230346434623361343130122438633465363161342d386136312d346263372d613234362d323730393635323031383262120c08e8b9f3820610c89790c9031a6133323034396236382d373837322d343039342d386536332d6430646435393839366138333a74656d706f72616c2d7379732d74712d7363616e6e65723a38623536323264302d373266342d346330362d386335652d346230346434623361343130	Proto3
\.


--
-- Data for Name: namespace_metadata; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.namespace_metadata (partition_id, notification_version) FROM stdin;
54321	3
\.


--
-- Data for Name: namespaces; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.namespaces (partition_id, id, name, notification_version, data, data_encoding, is_global) FROM stdin;
54321	\\x32049b68787240948e63d0dd59896a83	temporal-system	1	\\x0a780a2433323034396236382d373837322d343039342d386536332d64306464353938393661383310011a0f74656d706f72616c2d73797374656d222254656d706f72616c20696e7465726e616c2073797374656d206e616d6573706163652a1974656d706f72616c2d636f72654074656d706f72616c2e696f120a0a040880f524200130011a100a06616374697665120661637469766528ffffffffffffffffff01	Proto3	f
54321	\\x26f80ced0ead4534b085ff8c0643031c	default	2	\\x0a580a2432366638306365642d306561642d343533342d623038352d66663863303634333033316310011a0764656661756c74222544656661756c74206e616d65737061636520666f722054656d706f72616c2053657276657212660a040880a3051a0020022a2a66696c653a2f2f2f7661722f6c69622f74656d706f72616c2f617263686976616c2f74656d706f72616c30023a2c66696c653a2f2f2f7661722f6c69622f74656d706f72616c2f617263686976616c2f7669736962696c6974791a100a066163746976651206616374697665	Proto3	f
\.


--
-- Data for Name: queue; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.queue (queue_type, message_id, message_payload, message_encoding) FROM stdin;
\.


--
-- Data for Name: queue_metadata; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.queue_metadata (queue_type, data, data_encoding) FROM stdin;
1	\\x7b7d	Json
-1	\\x7b7d	Json
\.


--
-- Data for Name: replication_tasks; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.replication_tasks (shard_id, task_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: replication_tasks_dlq; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.replication_tasks_dlq (source_cluster_name, shard_id, task_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: request_cancel_info_maps; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.request_cancel_info_maps (shard_id, namespace_id, workflow_id, run_id, initiated_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: schema_update_history; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.schema_update_history (version_partition, year, month, update_time, description, manifest_md5, new_version, old_version) FROM stdin;
0	2021	3	2021-03-21 23:09:17.543434	initial version		0.0	0
0	2021	3	2021-03-21 23:09:17.807128	base version of schema	55b84ca114ac34d84bdc5f52c198fa33	1.0	0.0
0	2021	3	2021-03-21 23:09:17.80979	schema update for cluster metadata	58f06841bbb187cb210db32a090c21ee	1.1	1.0
0	2021	3	2021-03-21 23:09:17.811408	schema update for RPC replication	c6bdeea21882e2625038927a84929b16	1.2	1.1
0	2021	3	2021-03-21 23:09:17.815148	schema update for kafka deprecation	3beee7d470421674194475f94b58d89b	1.3	1.2
0	2021	3	2021-03-21 23:09:17.816468	schema update for cluster metadata cleanup	c53e2e9cea5660c8a1f3b2ac73cdb138	1.4	1.3
\.


--
-- Data for Name: schema_version; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.schema_version (version_partition, db_name, creation_time, curr_version, min_compatible_version) FROM stdin;
0	temporal	2021-03-21 23:09:17.816194	1.4	1.0
\.


--
-- Data for Name: shards; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.shards (shard_id, range_id, data, data_encoding) FROM stdin;
1	1	\\x080110011a0d31302e312e302e353a3732333430014802	Proto3
3	1	\\x080310011a0d31302e312e302e353a3732333430014802	Proto3
7	1	\\x080710011a0d31302e312e302e353a3732333430014802	Proto3
10	1	\\x080a10011a0d31302e312e302e353a3732333430014802	Proto3
5	1	\\x080510011a0d31302e312e302e353a3732333430014802	Proto3
11	1	\\x080b10011a0d31302e312e302e353a3732333430014802	Proto3
9	1	\\x080910011a0d31302e312e302e353a3732333430014802	Proto3
6	1	\\x080610011a0d31302e312e302e353a3732333430014802	Proto3
8	1	\\x080810011a0d31302e312e302e353a3732333430014802	Proto3
2	1	\\x080210011a0d31302e312e302e353a3732333430014802	Proto3
14	1	\\x080e10011a0d31302e312e302e353a3732333430014802	Proto3
16	1	\\x081010011a0d31302e312e302e353a3732333430014802	Proto3
4	1	\\x080410011a0d31302e312e302e353a3732333430014802	Proto3
13	1	\\x080d10011a0d31302e312e302e353a3732333430014802	Proto3
12	1	\\x080c10011a0d31302e312e302e353a3732333430014802	Proto3
15	1	\\x080f10011a0d31302e312e302e353a3732333430014802	Proto3
\.


--
-- Data for Name: signal_info_maps; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.signal_info_maps (shard_id, namespace_id, workflow_id, run_id, initiated_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: signals_requested_sets; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.signals_requested_sets (shard_id, namespace_id, workflow_id, run_id, signal_id) FROM stdin;
\.


--
-- Data for Name: task_queues; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.task_queues (range_hash, task_queue_id, range_id, data, data_encoding) FROM stdin;
1502813099	\\x32049b68787240948e63d0dd59896a836561346434626234623434313a66643265396231612d623363362d343662392d386333352d38343130363233323937613701	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312316561346434626234623434313a66643265396231612d623363362d343662392d386333352d38343130363233323937613718012002320b08a1ddf8820610a6a680223a0b08a1baf3820610b89f8022	Proto3
940296977	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d617263686976616c2d74712f3101	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121c2f5f7379732f74656d706f72616c2d617263686976616c2d74712f31180120013a0b08a1baf3820610dc8bc822	Proto3
653791233	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f3102	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312262f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f31180220013a0b08a1baf3820610d194da22	Proto3
1410825331	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d3002	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d30180220013a0b08a1baf3820610c28d8623	Proto3
3095716534	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d626174636865722d7461736b717565756502	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121e74656d706f72616c2d7379732d626174636865722d7461736b7175657565180220013a0b08a1baf3820610f2ec8e23	Proto3
2063506710	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d617263686976616c2d747101	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121474656d706f72616c2d617263686976616c2d7471180120013a0b08a1baf38206109cd1ca23	Proto3
1994493189	\\x32049b68787240948e63d0dd59896a836561346434626234623434313a61616336633234302d393530662d343065332d396130352d38353531313136653639373301	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312316561346434626234623434313a61616336633234302d393530662d343065332d396130352d38353531313136653639373318012002320b08a1ddf8820610c2dffd223a0b08a1baf382061095d6fd22	Proto3
4095103286	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f3102	1\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312322f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f31180220013a0b08a1baf38206109bcfeb23	Proto3
1332228876	\\x32049b68787240948e63d0dd59896a836561346434626234623434313a36326232346637372d393431352d343336342d616534332d31663134366537316561326601	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312316561346434626234623434313a36326232346637372d393431352d343336342d616534332d31663134366537316561326618012002320b08a1ddf8820610fa8293243a0b08a1baf3820610fefa9224	Proto3
3469555445	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d626174636865722d7461736b717565756501	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121e74656d706f72616c2d7379732d626174636865722d7461736b7175657565180120013a0b08a1baf3820610dfaee824	Proto3
1018868252	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f3202	1\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312322f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f32180220013a0b08a1baf3820610cbab8c24	Proto3
2528910666	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c69637901	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122a74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c696379180120013a0b08a1baf382061081b68324	Proto3
3617866575	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f3201	1\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312322f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f32180120013a0b08a1baf3820610efcdba27	Proto3
1177789365	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d617263686976616c2d74712f3302	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121c2f5f7379732f74656d706f72616c2d617263686976616c2d74712f33180220013a0b08a0baf3820610dad79721	Proto3
3681167674	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f3202	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122b2f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f32180220013a0b08a0baf3820610b1849221	Proto3
2662461164	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f3102	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122b2f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f31180220013a0b08a0baf38206109fd4a922	Proto3
289827042	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d617263686976616c2d74712f3102	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121c2f5f7379732f74656d706f72616c2d617263686976616c2d74712f31180220013a0b08a0baf3820610e9d7b922	Proto3
430461988	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f3301	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122b2f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f33180120013a0b08a0baf3820610d493bd22	Proto3
740397391	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d617263686976616c2d74712f3301	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121c2f5f7379732f74656d706f72616c2d617263686976616c2d74712f33180120013a0b08a0baf382061087d6b023	Proto3
1693213168	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f3302	1\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312322f5f7379732f74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c6963792f33180220013a0b08a0baf3820610ddb1fb23	Proto3
739332331	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f3201	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312262f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f32180120013a0b08a0baf3820610dde58024	Proto3
481579558	\\x32049b68787240948e63d0dd59896a836561346434626234623434313a30636231303935612d366365342d343133332d623631652d65366137323333313833336201	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312316561346434626234623434313a30636231303935612d366365342d343133332d623631652d65366137323333313833336218012002320b08a1ddf8820610f89fee1d3a0b08a1baf38206108499ee1d	Proto3
70786998	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f3101	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122b2f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f31180120013a0b08a1baf3820610fabec31f	Proto3
2358430835	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d617263686976616c2d74712f3202	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121c2f5f7379732f74656d706f72616c2d617263686976616c2d74712f32180220013a0b08a1baf3820610efe1eb1f	Proto3
3662736275	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f3302	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122b2f5f7379732f74656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d302f33180220013a0b08a1baf38206108f8eef1f	Proto3
3963122975	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f3202	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312262f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f32180220013a0b08a1baf38206108cb38521	Proto3
4214421317	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d3001	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122374656d706f72616c2d7379732d74712d7363616e6e65722d7461736b71756575652d30180120013a0b08a1baf382061080949521	Proto3
3597285451	\\x32049b68787240948e63d0dd59896a832f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f3101	1	\\x0a2433323034396236382d373837322d343039342d386536332d64306464353938393661383312262f5f7379732f74656d706f72616c2d7379732d626174636865722d7461736b71756575652f31180120013a0b08a1baf3820610909c9823	Proto3
1688886821	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c69637902	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833122a74656d706f72616c2d7379732d70726f636573736f722d706172656e742d636c6f73652d706f6c696379180220013a0b08a1baf382061081f6e824	Proto3
288707420	\\x32049b68787240948e63d0dd59896a8374656d706f72616c2d617263686976616c2d747102	1	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121474656d706f72616c2d617263686976616c2d7471180220013a0b08a1baf38206108190e924	Proto3
\.


--
-- Data for Name: tasks; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.tasks (range_hash, task_queue_id, task_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: timer_info_maps; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.timer_info_maps (shard_id, namespace_id, workflow_id, run_id, timer_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: timer_tasks; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.timer_tasks (shard_id, visibility_timestamp, task_id, data, data_encoding) FROM stdin;
8	2021-03-31 00:00:00.958136	1048579	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121774656d706f72616c2d7379732d74712d7363616e6e65721a2438623536323264302d373266342d346330362d386335652d346230346434623361343130200f508380405a0c0880f78e830610ebfaefc803	Proto3
8	2021-03-26 00:00:00.958136	1048580	\\x0a2433323034396236382d373837322d343039342d386536332d643064643539383936613833121774656d706f72616c2d7379732d74712d7363616e6e65721a2438623536323264302d373266342d346330362d386335652d34623034643462336134313020123002508480405a0c0880c8f4820610ebfaefc803	Proto3
\.


--
-- Data for Name: transfer_tasks; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.transfer_tasks (shard_id, task_id, data, data_encoding) FROM stdin;
\.


--
-- Data for Name: visibility_tasks; Type: TABLE DATA; Schema: public; Owner: temporal
--

COPY public.visibility_tasks (shard_id, task_id, data, data_encoding) FROM stdin;
\.


--
-- Name: buffered_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: temporal
--

SELECT pg_catalog.setval('public.buffered_events_id_seq', 1, false);


--
-- Name: activity_info_maps activity_info_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.activity_info_maps
    ADD CONSTRAINT activity_info_maps_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, schedule_id);


--
-- Name: buffered_events buffered_events_id_key; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.buffered_events
    ADD CONSTRAINT buffered_events_id_key UNIQUE (id);


--
-- Name: buffered_events buffered_events_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.buffered_events
    ADD CONSTRAINT buffered_events_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, id);


--
-- Name: child_execution_info_maps child_execution_info_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.child_execution_info_maps
    ADD CONSTRAINT child_execution_info_maps_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, initiated_id);


--
-- Name: cluster_membership cluster_membership_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.cluster_membership
    ADD CONSTRAINT cluster_membership_pkey PRIMARY KEY (membership_partition, host_id);


--
-- Name: cluster_metadata cluster_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.cluster_metadata
    ADD CONSTRAINT cluster_metadata_pkey PRIMARY KEY (metadata_partition);


--
-- Name: current_executions current_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.current_executions
    ADD CONSTRAINT current_executions_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id);


--
-- Name: executions executions_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.executions
    ADD CONSTRAINT executions_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id);


--
-- Name: history_node history_node_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.history_node
    ADD CONSTRAINT history_node_pkey PRIMARY KEY (shard_id, tree_id, branch_id, node_id, txn_id);


--
-- Name: history_tree history_tree_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.history_tree
    ADD CONSTRAINT history_tree_pkey PRIMARY KEY (shard_id, tree_id, branch_id);


--
-- Name: namespace_metadata namespace_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.namespace_metadata
    ADD CONSTRAINT namespace_metadata_pkey PRIMARY KEY (partition_id);


--
-- Name: namespaces namespaces_name_key; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.namespaces
    ADD CONSTRAINT namespaces_name_key UNIQUE (name);


--
-- Name: namespaces namespaces_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.namespaces
    ADD CONSTRAINT namespaces_pkey PRIMARY KEY (partition_id, id);


--
-- Name: queue_metadata queue_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.queue_metadata
    ADD CONSTRAINT queue_metadata_pkey PRIMARY KEY (queue_type);


--
-- Name: queue queue_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.queue
    ADD CONSTRAINT queue_pkey PRIMARY KEY (queue_type, message_id);


--
-- Name: replication_tasks_dlq replication_tasks_dlq_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.replication_tasks_dlq
    ADD CONSTRAINT replication_tasks_dlq_pkey PRIMARY KEY (source_cluster_name, shard_id, task_id);


--
-- Name: replication_tasks replication_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.replication_tasks
    ADD CONSTRAINT replication_tasks_pkey PRIMARY KEY (shard_id, task_id);


--
-- Name: request_cancel_info_maps request_cancel_info_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.request_cancel_info_maps
    ADD CONSTRAINT request_cancel_info_maps_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, initiated_id);


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
-- Name: shards shards_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.shards
    ADD CONSTRAINT shards_pkey PRIMARY KEY (shard_id);


--
-- Name: signal_info_maps signal_info_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.signal_info_maps
    ADD CONSTRAINT signal_info_maps_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, initiated_id);


--
-- Name: signals_requested_sets signals_requested_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.signals_requested_sets
    ADD CONSTRAINT signals_requested_sets_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, signal_id);


--
-- Name: task_queues task_queues_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.task_queues
    ADD CONSTRAINT task_queues_pkey PRIMARY KEY (range_hash, task_queue_id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (range_hash, task_queue_id, task_id);


--
-- Name: timer_info_maps timer_info_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.timer_info_maps
    ADD CONSTRAINT timer_info_maps_pkey PRIMARY KEY (shard_id, namespace_id, workflow_id, run_id, timer_id);


--
-- Name: timer_tasks timer_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.timer_tasks
    ADD CONSTRAINT timer_tasks_pkey PRIMARY KEY (shard_id, visibility_timestamp, task_id);


--
-- Name: transfer_tasks transfer_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.transfer_tasks
    ADD CONSTRAINT transfer_tasks_pkey PRIMARY KEY (shard_id, task_id);


--
-- Name: visibility_tasks visibility_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: temporal
--

ALTER TABLE ONLY public.visibility_tasks
    ADD CONSTRAINT visibility_tasks_pkey PRIMARY KEY (shard_id, task_id);


--
-- Name: cm_idx_lasthb; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX cm_idx_lasthb ON public.cluster_membership USING btree (last_heartbeat);


--
-- Name: cm_idx_recordexpiry; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX cm_idx_recordexpiry ON public.cluster_membership USING btree (record_expiry);


--
-- Name: cm_idx_rolehost; Type: INDEX; Schema: public; Owner: temporal
--

CREATE UNIQUE INDEX cm_idx_rolehost ON public.cluster_membership USING btree (role, host_id);


--
-- Name: cm_idx_rolelasthb; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX cm_idx_rolelasthb ON public.cluster_membership USING btree (role, last_heartbeat);


--
-- Name: cm_idx_rpchost; Type: INDEX; Schema: public; Owner: temporal
--

CREATE INDEX cm_idx_rpchost ON public.cluster_membership USING btree (rpc_address, role);


--
-- PostgreSQL database dump complete
--

