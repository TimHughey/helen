--
-- PostgreSQL database dump
--

-- Dumped from database version 13.2
-- Dumped by pg_dump version 13.2

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

SET default_table_access_method = heap;

--
-- Name: pwm_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pwm_alias (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    device_id bigint,
    description character varying(50) DEFAULT '<none>'::character varying,
    ttl_ms integer DEFAULT 60000 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    pio integer NOT NULL,
    cmd character varying(32) DEFAULT 'unknown'::character varying NOT NULL
);


--
-- Name: pwm_alias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pwm_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pwm_alias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pwm_alias_id_seq OWNED BY public.pwm_alias.id;


--
-- Name: pwm_cmd; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pwm_cmd (
    id bigint NOT NULL,
    refid uuid,
    acked boolean DEFAULT false NOT NULL,
    orphan boolean DEFAULT false NOT NULL,
    rt_latency_us integer DEFAULT 0 NOT NULL,
    sent_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    ack_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    cmd character varying(32),
    alias_id bigint
);


--
-- Name: pwm_cmd_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pwm_cmd_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pwm_cmd_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pwm_cmd_id_seq OWNED BY public.pwm_cmd.id;


--
-- Name: pwm_device; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pwm_device (
    id bigint NOT NULL,
    device character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    dev_latency_us integer DEFAULT 0,
    last_seen_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    pio_count integer NOT NULL
);


--
-- Name: pwm_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pwm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pwm_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pwm_id_seq OWNED BY public.pwm_device.id;


--
-- Name: remote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.remote (
    id bigint NOT NULL,
    host character varying(20) NOT NULL,
    name character varying(35) NOT NULL,
    firmware_vsn character varying(32) DEFAULT '0000000'::character varying NOT NULL,
    last_start_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    last_seen_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    reset_reason character varying(25) DEFAULT 'unknown'::character varying,
    ap_rssi integer DEFAULT 0,
    ap_pri_chan integer DEFAULT 0,
    heap_free integer DEFAULT 0,
    heap_min integer DEFAULT 0,
    uptime_us bigint DEFAULT 0,
    idf_vsn character varying(32),
    app_elf_sha256 character varying(255),
    build_date character varying(16),
    build_time character varying(16),
    bssid character varying(255) DEFAULT 'xx:xx:xx:xx:xx:xx'::character varying,
    profile character varying(255) DEFAULT 'default'::character varying NOT NULL,
    firmware_etag character varying(24) DEFAULT '<none>'::character varying NOT NULL
);


--
-- Name: remote_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.remote_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: remote_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.remote_id_seq OWNED BY public.remote.id;


--
-- Name: remote_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.remote_profile (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    version uuid NOT NULL,
    dalsemi_enable boolean DEFAULT true NOT NULL,
    dalsemi_core_stack integer DEFAULT 1536 NOT NULL,
    dalsemi_core_priority integer DEFAULT 1 NOT NULL,
    dalsemi_report_stack integer DEFAULT 3072 NOT NULL,
    dalsemi_report_priority integer DEFAULT 13 NOT NULL,
    dalsemi_command_stack integer DEFAULT 3072 NOT NULL,
    dalsemi_command_priority integer DEFAULT 14 NOT NULL,
    dalsemi_core_interval_ms integer DEFAULT 30000 NOT NULL,
    dalsemi_report_interval_ms integer DEFAULT 7000 NOT NULL,
    i2c_enable boolean DEFAULT true NOT NULL,
    i2c_use_multiplexer boolean DEFAULT false NOT NULL,
    i2c_core_stack integer DEFAULT 1536 NOT NULL,
    i2c_core_priority integer DEFAULT 1 NOT NULL,
    i2c_report_stack integer DEFAULT 3072 NOT NULL,
    i2c_report_priority integer DEFAULT 13 NOT NULL,
    i2c_command_stack integer DEFAULT 3072 NOT NULL,
    i2c_command_priority integer DEFAULT 14 NOT NULL,
    i2c_core_interval_ms integer DEFAULT 7000 NOT NULL,
    i2c_report_interval_ms integer DEFAULT 7000 NOT NULL,
    pwm_enable boolean DEFAULT true NOT NULL,
    pwm_core_stack integer DEFAULT 1536 NOT NULL,
    pwm_core_priority integer DEFAULT 1 NOT NULL,
    pwm_report_stack integer DEFAULT 2048 NOT NULL,
    pwm_report_priority integer DEFAULT 12 NOT NULL,
    pwm_report_interval_ms integer DEFAULT 7000 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    description character varying(255) DEFAULT ' '::character varying,
    watch_stacks boolean DEFAULT false NOT NULL,
    core_loop_interval_ms integer DEFAULT 1000 NOT NULL,
    core_timestamp_ms integer DEFAULT 360000 NOT NULL,
    lightdesk_enable boolean DEFAULT false
);


--
-- Name: remote_profile_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.remote_profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: remote_profile_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.remote_profile_id_seq OWNED BY public.remote_profile.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: sensor_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sensor_alias (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    device_id bigint,
    description character varying(50) DEFAULT '<none>'::character varying,
    type character varying(20) DEFAULT 'auto'::character varying NOT NULL,
    ttl_ms integer DEFAULT 60000 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sensor_alias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sensor_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensor_alias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sensor_alias_id_seq OWNED BY public.sensor_alias.id;


--
-- Name: sensor_datapoint; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sensor_datapoint (
    id bigint NOT NULL,
    temp_f real,
    temp_c real,
    relhum real,
    capacitance real,
    reading_at timestamp without time zone,
    device_id bigint
);


--
-- Name: sensor_datapoint_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sensor_datapoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensor_datapoint_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sensor_datapoint_id_seq OWNED BY public.sensor_datapoint.id;


--
-- Name: sensor_device; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sensor_device (
    id bigint NOT NULL,
    device character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    dev_latency_us integer DEFAULT 0 NOT NULL,
    last_seen_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sensor_device_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sensor_device_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensor_device_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sensor_device_id_seq OWNED BY public.sensor_device.id;


--
-- Name: switch_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.switch_alias (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    device_id bigint,
    description character varying(50),
    pio integer NOT NULL,
    ttl_ms integer DEFAULT 60000,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    cmd character varying(255) DEFAULT 'unknown'::character varying NOT NULL
);


--
-- Name: switch_alias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.switch_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: switch_alias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.switch_alias_id_seq OWNED BY public.switch_alias.id;


--
-- Name: switch_cmd; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.switch_cmd (
    id bigint NOT NULL,
    refid uuid NOT NULL,
    acked boolean DEFAULT false NOT NULL,
    orphan boolean DEFAULT false NOT NULL,
    rt_latency_us integer DEFAULT 0 NOT NULL,
    sent_at timestamp without time zone NOT NULL,
    ack_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    alias_id bigint,
    cmd character varying(32)
);


--
-- Name: switch_cmd_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.switch_cmd_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: switch_cmd_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.switch_cmd_id_seq OWNED BY public.switch_cmd.id;


--
-- Name: switch_device; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.switch_device (
    id bigint NOT NULL,
    device character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    dev_latency_us integer DEFAULT 0 NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    pio_count integer DEFAULT 8 NOT NULL
);


--
-- Name: switch_device_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.switch_device_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: switch_device_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.switch_device_id_seq OWNED BY public.switch_device.id;


--
-- Name: worker_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.worker_config (
    id bigint NOT NULL,
    module character varying(60) NOT NULL,
    comment text DEFAULT '<none>'::text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: worker_config_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.worker_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: worker_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.worker_config_id_seq OWNED BY public.worker_config.id;


--
-- Name: worker_config_line; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.worker_config_line (
    id bigint NOT NULL,
    num integer NOT NULL,
    line text DEFAULT ' '::text NOT NULL,
    worker_config_id bigint
);


--
-- Name: worker_config_line_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.worker_config_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: worker_config_line_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.worker_config_line_id_seq OWNED BY public.worker_config_line.id;


--
-- Name: pwm_alias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_alias ALTER COLUMN id SET DEFAULT nextval('public.pwm_alias_id_seq'::regclass);


--
-- Name: pwm_cmd id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_cmd ALTER COLUMN id SET DEFAULT nextval('public.pwm_cmd_id_seq'::regclass);


--
-- Name: pwm_device id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_device ALTER COLUMN id SET DEFAULT nextval('public.pwm_id_seq'::regclass);


--
-- Name: remote id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote ALTER COLUMN id SET DEFAULT nextval('public.remote_id_seq'::regclass);


--
-- Name: remote_profile id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_profile ALTER COLUMN id SET DEFAULT nextval('public.remote_profile_id_seq'::regclass);


--
-- Name: sensor_alias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_alias ALTER COLUMN id SET DEFAULT nextval('public.sensor_alias_id_seq'::regclass);


--
-- Name: sensor_datapoint id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_datapoint ALTER COLUMN id SET DEFAULT nextval('public.sensor_datapoint_id_seq'::regclass);


--
-- Name: sensor_device id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_device ALTER COLUMN id SET DEFAULT nextval('public.sensor_device_id_seq'::regclass);


--
-- Name: switch_alias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_alias ALTER COLUMN id SET DEFAULT nextval('public.switch_alias_id_seq'::regclass);


--
-- Name: switch_cmd id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_cmd ALTER COLUMN id SET DEFAULT nextval('public.switch_cmd_id_seq'::regclass);


--
-- Name: switch_device id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_device ALTER COLUMN id SET DEFAULT nextval('public.switch_device_id_seq'::regclass);


--
-- Name: worker_config id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_config ALTER COLUMN id SET DEFAULT nextval('public.worker_config_id_seq'::regclass);


--
-- Name: worker_config_line id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_config_line ALTER COLUMN id SET DEFAULT nextval('public.worker_config_line_id_seq'::regclass);


--
-- Name: pwm_alias pwm_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_alias
    ADD CONSTRAINT pwm_alias_pkey PRIMARY KEY (id);


--
-- Name: pwm_cmd pwm_cmd_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_cmd
    ADD CONSTRAINT pwm_cmd_pkey PRIMARY KEY (id);


--
-- Name: pwm_device pwm_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_device
    ADD CONSTRAINT pwm_pkey PRIMARY KEY (id);


--
-- Name: remote remote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote
    ADD CONSTRAINT remote_pkey PRIMARY KEY (id);


--
-- Name: remote_profile remote_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_profile
    ADD CONSTRAINT remote_profile_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sensor_alias sensor_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_alias
    ADD CONSTRAINT sensor_alias_pkey PRIMARY KEY (id);


--
-- Name: sensor_datapoint sensor_datapoint_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_datapoint
    ADD CONSTRAINT sensor_datapoint_pkey PRIMARY KEY (id);


--
-- Name: sensor_device sensor_device_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_device
    ADD CONSTRAINT sensor_device_pkey PRIMARY KEY (id);


--
-- Name: switch_alias switch_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_alias
    ADD CONSTRAINT switch_alias_pkey PRIMARY KEY (id);


--
-- Name: switch_cmd switch_cmd_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_cmd
    ADD CONSTRAINT switch_cmd_pkey PRIMARY KEY (id);


--
-- Name: switch_device switch_device_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_device
    ADD CONSTRAINT switch_device_pkey PRIMARY KEY (id);


--
-- Name: worker_config_line worker_config_line_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_config_line
    ADD CONSTRAINT worker_config_line_pkey PRIMARY KEY (id);


--
-- Name: worker_config worker_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_config
    ADD CONSTRAINT worker_config_pkey PRIMARY KEY (id);


--
-- Name: pwm_alias_device_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_alias_device_id_index ON public.pwm_alias USING btree (device_id);


--
-- Name: pwm_alias_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_alias_name_index ON public.pwm_alias USING btree (name);


--
-- Name: pwm_cmd_acked_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_acked_index ON public.pwm_cmd USING btree (acked);


--
-- Name: pwm_cmd_alias_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_alias_id_index ON public.pwm_cmd USING btree (alias_id);


--
-- Name: pwm_cmd_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_inserted_at_index ON public.pwm_cmd USING brin (inserted_at);


--
-- Name: pwm_cmd_orphan_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_orphan_index ON public.pwm_cmd USING btree (orphan);


--
-- Name: pwm_cmd_refid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_cmd_refid_index ON public.pwm_cmd USING btree (refid);


--
-- Name: pwm_cmd_sent_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_sent_at_index ON public.pwm_cmd USING btree (sent_at);


--
-- Name: pwm_device_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_device_unique_index ON public.pwm_device USING btree (device);


--
-- Name: remote_host_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX remote_host_index ON public.remote USING btree (host);


--
-- Name: remote_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX remote_name_index ON public.remote USING btree (name);


--
-- Name: remote_profile_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX remote_profile_name_index ON public.remote_profile USING btree (name);


--
-- Name: sensor_alias_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sensor_alias_name_index ON public.sensor_alias USING btree (name);


--
-- Name: sensor_datapoint_reading_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sensor_datapoint_reading_at_index ON public.sensor_datapoint USING btree (reading_at);


--
-- Name: sensor_device_last_seen_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sensor_device_last_seen_at_index ON public.sensor_device USING btree (last_seen_at);


--
-- Name: sensor_device_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sensor_device_unique_index ON public.sensor_device USING btree (device);


--
-- Name: switch_alias_device_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_alias_device_id_index ON public.switch_alias USING btree (device_id);


--
-- Name: switch_alias_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX switch_alias_name_index ON public.switch_alias USING btree (name);


--
-- Name: switch_cmd_acked_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_cmd_acked_index ON public.switch_cmd USING btree (acked);


--
-- Name: switch_cmd_alias_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_cmd_alias_id_index ON public.switch_cmd USING btree (alias_id);


--
-- Name: switch_cmd_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_cmd_inserted_at_index ON public.switch_cmd USING brin (inserted_at);


--
-- Name: switch_cmd_refid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX switch_cmd_refid_index ON public.switch_cmd USING btree (refid);


--
-- Name: switch_cmd_sent_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_cmd_sent_at_index ON public.switch_cmd USING brin (sent_at);


--
-- Name: switch_device_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX switch_device_id_index ON public.switch_device USING btree (id);


--
-- Name: switch_device_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX switch_device_unique_index ON public.switch_device USING btree (device);


--
-- Name: worker_config_line_worker_config_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX worker_config_line_worker_config_id_index ON public.worker_config_line USING btree (worker_config_id);


--
-- Name: worker_config_module_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX worker_config_module_updated_at_index ON public.worker_config USING btree (module, updated_at);


--
-- Name: pwm_alias pwm_alias_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_alias
    ADD CONSTRAINT pwm_alias_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.pwm_device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: pwm_cmd pwm_cmd_alias_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_cmd
    ADD CONSTRAINT pwm_cmd_alias_id_fkey FOREIGN KEY (alias_id) REFERENCES public.pwm_alias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sensor_alias sensor_alias_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_alias
    ADD CONSTRAINT sensor_alias_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.sensor_device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sensor_datapoint sensor_datapoint_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensor_datapoint
    ADD CONSTRAINT sensor_datapoint_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.sensor_device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: switch_alias switch_alias_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_alias
    ADD CONSTRAINT switch_alias_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.switch_device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: switch_cmd switch_cmd_alias_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_cmd
    ADD CONSTRAINT switch_cmd_alias_id_fkey FOREIGN KEY (alias_id) REFERENCES public.switch_alias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: worker_config_line worker_config_line_worker_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_config_line
    ADD CONSTRAINT worker_config_line_worker_config_id_fkey FOREIGN KEY (worker_config_id) REFERENCES public.worker_config(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20171217150128);
INSERT INTO public."schema_migrations" (version) VALUES (20171224164529);
INSERT INTO public."schema_migrations" (version) VALUES (20171224225113);
INSERT INTO public."schema_migrations" (version) VALUES (20171228191703);
INSERT INTO public."schema_migrations" (version) VALUES (20171229001359);
INSERT INTO public."schema_migrations" (version) VALUES (20171231182344);
INSERT INTO public."schema_migrations" (version) VALUES (20180101153253);
INSERT INTO public."schema_migrations" (version) VALUES (20180102171624);
INSERT INTO public."schema_migrations" (version) VALUES (20180102175335);
INSERT INTO public."schema_migrations" (version) VALUES (20180217212153);
INSERT INTO public."schema_migrations" (version) VALUES (20180218021213);
INSERT INTO public."schema_migrations" (version) VALUES (20180222165118);
INSERT INTO public."schema_migrations" (version) VALUES (20180222184042);
INSERT INTO public."schema_migrations" (version) VALUES (20180305193804);
INSERT INTO public."schema_migrations" (version) VALUES (20180307143400);
INSERT INTO public."schema_migrations" (version) VALUES (20180517201719);
INSERT INTO public."schema_migrations" (version) VALUES (20180708221600);
INSERT INTO public."schema_migrations" (version) VALUES (20180709181021);
INSERT INTO public."schema_migrations" (version) VALUES (20190308124055);
INSERT INTO public."schema_migrations" (version) VALUES (20190316032007);
INSERT INTO public."schema_migrations" (version) VALUES (20190317155502);
INSERT INTO public."schema_migrations" (version) VALUES (20190320124824);
INSERT INTO public."schema_migrations" (version) VALUES (20190416130912);
INSERT INTO public."schema_migrations" (version) VALUES (20190417011910);
INSERT INTO public."schema_migrations" (version) VALUES (20191018110319);
INSERT INTO public."schema_migrations" (version) VALUES (20191022013914);
INSERT INTO public."schema_migrations" (version) VALUES (20200105131440);
INSERT INTO public."schema_migrations" (version) VALUES (20200115151705);
INSERT INTO public."schema_migrations" (version) VALUES (20200116024319);
INSERT INTO public."schema_migrations" (version) VALUES (20200127033742);
INSERT INTO public."schema_migrations" (version) VALUES (20200128032134);
INSERT INTO public."schema_migrations" (version) VALUES (20200210202655);
INSERT INTO public."schema_migrations" (version) VALUES (20200212175538);
INSERT INTO public."schema_migrations" (version) VALUES (20200212183409);
INSERT INTO public."schema_migrations" (version) VALUES (20200213192845);
INSERT INTO public."schema_migrations" (version) VALUES (20200215173921);
INSERT INTO public."schema_migrations" (version) VALUES (20200217154954);
INSERT INTO public."schema_migrations" (version) VALUES (20200302001850);
INSERT INTO public."schema_migrations" (version) VALUES (20200302155853);
INSERT INTO public."schema_migrations" (version) VALUES (20200309213120);
INSERT INTO public."schema_migrations" (version) VALUES (20200311130709);
INSERT INTO public."schema_migrations" (version) VALUES (20200313132136);
INSERT INTO public."schema_migrations" (version) VALUES (20200314125818);
INSERT INTO public."schema_migrations" (version) VALUES (20200314144615);
INSERT INTO public."schema_migrations" (version) VALUES (20200314152346);
INSERT INTO public."schema_migrations" (version) VALUES (20200314233840);
INSERT INTO public."schema_migrations" (version) VALUES (20200320022913);
INSERT INTO public."schema_migrations" (version) VALUES (20200325211220);
INSERT INTO public."schema_migrations" (version) VALUES (20200506182825);
INSERT INTO public."schema_migrations" (version) VALUES (20200511174457);
INSERT INTO public."schema_migrations" (version) VALUES (20200512174739);
INSERT INTO public."schema_migrations" (version) VALUES (20200512185326);
INSERT INTO public."schema_migrations" (version) VALUES (20200513205755);
INSERT INTO public."schema_migrations" (version) VALUES (20200522043654);
INSERT INTO public."schema_migrations" (version) VALUES (20200525210412);
INSERT INTO public."schema_migrations" (version) VALUES (20200526171324);
INSERT INTO public."schema_migrations" (version) VALUES (20200526172112);
INSERT INTO public."schema_migrations" (version) VALUES (20200527115635);
INSERT INTO public."schema_migrations" (version) VALUES (20200527161830);
INSERT INTO public."schema_migrations" (version) VALUES (20200529123232);
INSERT INTO public."schema_migrations" (version) VALUES (20200529190741);
INSERT INTO public."schema_migrations" (version) VALUES (20200602110652);
INSERT INTO public."schema_migrations" (version) VALUES (20200602194456);
INSERT INTO public."schema_migrations" (version) VALUES (20200603171602);
INSERT INTO public."schema_migrations" (version) VALUES (20200603180219);
INSERT INTO public."schema_migrations" (version) VALUES (20200605101957);
INSERT INTO public."schema_migrations" (version) VALUES (20200606154209);
INSERT INTO public."schema_migrations" (version) VALUES (20200607232505);
INSERT INTO public."schema_migrations" (version) VALUES (20200608133620);
INSERT INTO public."schema_migrations" (version) VALUES (20200614233621);
INSERT INTO public."schema_migrations" (version) VALUES (20200615131244);
INSERT INTO public."schema_migrations" (version) VALUES (20200615183810);
INSERT INTO public."schema_migrations" (version) VALUES (20200616131408);
INSERT INTO public."schema_migrations" (version) VALUES (20200617120412);
INSERT INTO public."schema_migrations" (version) VALUES (20200617172518);
INSERT INTO public."schema_migrations" (version) VALUES (20200619202154);
INSERT INTO public."schema_migrations" (version) VALUES (20200623215512);
INSERT INTO public."schema_migrations" (version) VALUES (20200624104559);
INSERT INTO public."schema_migrations" (version) VALUES (20200624125619);
INSERT INTO public."schema_migrations" (version) VALUES (20200624152332);
INSERT INTO public."schema_migrations" (version) VALUES (20201007141801);
INSERT INTO public."schema_migrations" (version) VALUES (20201007225427);
INSERT INTO public."schema_migrations" (version) VALUES (20201010000023);
INSERT INTO public."schema_migrations" (version) VALUES (20201124131225);
INSERT INTO public."schema_migrations" (version) VALUES (20210112020809);
INSERT INTO public."schema_migrations" (version) VALUES (20210112021115);
INSERT INTO public."schema_migrations" (version) VALUES (20210422175619);
INSERT INTO public."schema_migrations" (version) VALUES (20210422184410);
INSERT INTO public."schema_migrations" (version) VALUES (20210423114322);
INSERT INTO public."schema_migrations" (version) VALUES (20210423173102);
INSERT INTO public."schema_migrations" (version) VALUES (20210423210752);
INSERT INTO public."schema_migrations" (version) VALUES (20210424025741);
INSERT INTO public."schema_migrations" (version) VALUES (20210424215626);
INSERT INTO public."schema_migrations" (version) VALUES (20210425111302);
INSERT INTO public."schema_migrations" (version) VALUES (20210425155030);
INSERT INTO public."schema_migrations" (version) VALUES (20210425164121);
INSERT INTO public."schema_migrations" (version) VALUES (20210425165702);
INSERT INTO public."schema_migrations" (version) VALUES (20210425170202);
INSERT INTO public."schema_migrations" (version) VALUES (20210425182014);
INSERT INTO public."schema_migrations" (version) VALUES (20210426163156);
INSERT INTO public."schema_migrations" (version) VALUES (20210426164714);
INSERT INTO public."schema_migrations" (version) VALUES (20210426165842);
INSERT INTO public."schema_migrations" (version) VALUES (20210426232924);
INSERT INTO public."schema_migrations" (version) VALUES (20210426233059);
INSERT INTO public."schema_migrations" (version) VALUES (20210429024800);
INSERT INTO public."schema_migrations" (version) VALUES (20210429212232);
INSERT INTO public."schema_migrations" (version) VALUES (20210430120412);
INSERT INTO public."schema_migrations" (version) VALUES (20210430121001);
INSERT INTO public."schema_migrations" (version) VALUES (20210507003858);
INSERT INTO public."schema_migrations" (version) VALUES (20210507025645);
INSERT INTO public."schema_migrations" (version) VALUES (20210510013226);
