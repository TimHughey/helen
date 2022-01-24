--
-- PostgreSQL database dump
--

-- Dumped from database version 13.5
-- Dumped by pg_dump version 14.1

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
-- Name: command; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command (
    id bigint NOT NULL,
    dev_alias_id bigint,
    cmd character varying(32) NOT NULL,
    refid character varying(48) NOT NULL,
    acked boolean DEFAULT false NOT NULL,
    orphaned boolean DEFAULT false NOT NULL,
    sent_at timestamp without time zone NOT NULL,
    acked_at timestamp without time zone,
    rt_latency_us integer DEFAULT 0
);


--
-- Name: command_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.command_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: command_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.command_id_seq OWNED BY public.command.id;


--
-- Name: datapoint; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.datapoint (
    id bigint NOT NULL,
    dev_alias_id bigint,
    temp_c double precision,
    relhum double precision,
    reading_at timestamp without time zone
);


--
-- Name: datapoint_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.datapoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: datapoint_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.datapoint_id_seq OWNED BY public.datapoint.id;


--
-- Name: dev_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dev_alias (
    id bigint NOT NULL,
    device_id bigint,
    name character varying(128) NOT NULL,
    pio integer NOT NULL,
    description character varying(128),
    ttl_ms integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dev_alias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dev_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dev_alias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dev_alias_id_seq OWNED BY public.dev_alias.id;


--
-- Name: device; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device (
    id bigint NOT NULL,
    host_id bigint,
    ident character varying(128) NOT NULL,
    family character varying(24) NOT NULL,
    mutable boolean NOT NULL,
    pios integer NOT NULL,
    last_seen_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: device_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.device_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: device_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.device_id_seq OWNED BY public.device.id;


--
-- Name: host; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.host (
    id bigint NOT NULL,
    ident character varying(24) NOT NULL,
    name character varying(32) NOT NULL,
    profile character varying(32) NOT NULL,
    authorized boolean NOT NULL,
    firmware_vsn character varying(32),
    idf_vsn character varying(12),
    app_sha character varying(12),
    reset_reason character varying(24),
    build_at timestamp without time zone,
    last_start_at timestamp without time zone NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: host_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.host_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: host_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.host_id_seq OWNED BY public.host.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: command id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command ALTER COLUMN id SET DEFAULT nextval('public.command_id_seq'::regclass);


--
-- Name: datapoint id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datapoint ALTER COLUMN id SET DEFAULT nextval('public.datapoint_id_seq'::regclass);


--
-- Name: dev_alias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_alias ALTER COLUMN id SET DEFAULT nextval('public.dev_alias_id_seq'::regclass);


--
-- Name: device id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device ALTER COLUMN id SET DEFAULT nextval('public.device_id_seq'::regclass);


--
-- Name: host id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.host ALTER COLUMN id SET DEFAULT nextval('public.host_id_seq'::regclass);


--
-- Name: command command_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command
    ADD CONSTRAINT command_pkey PRIMARY KEY (id);


--
-- Name: datapoint datapoint_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datapoint
    ADD CONSTRAINT datapoint_pkey PRIMARY KEY (id);


--
-- Name: dev_alias dev_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_alias
    ADD CONSTRAINT dev_alias_pkey PRIMARY KEY (id);


--
-- Name: device device_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device
    ADD CONSTRAINT device_pkey PRIMARY KEY (id);


--
-- Name: host host_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.host
    ADD CONSTRAINT host_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: command_dev_alias_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_dev_alias_id_index ON public.command USING btree (dev_alias_id);


--
-- Name: command_refid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_refid_index ON public.command USING btree (refid);


--
-- Name: command_sent_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_sent_at_index ON public.command USING btree (sent_at);


--
-- Name: datapoint_reading_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX datapoint_reading_at_index ON public.datapoint USING btree (reading_at);


--
-- Name: dev_alias_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dev_alias_name_index ON public.dev_alias USING btree (name);


--
-- Name: device_ident_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX device_ident_index ON public.device USING btree (ident);


--
-- Name: host_ident_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX host_ident_index ON public.host USING btree (ident);


--
-- Name: host_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX host_name_index ON public.host USING btree (name);


--
-- Name: command command_dev_alias_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command
    ADD CONSTRAINT command_dev_alias_id_fkey FOREIGN KEY (dev_alias_id) REFERENCES public.dev_alias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: datapoint datapoint_dev_alias_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datapoint
    ADD CONSTRAINT datapoint_dev_alias_id_fkey FOREIGN KEY (dev_alias_id) REFERENCES public.dev_alias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: dev_alias dev_alias_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_alias
    ADD CONSTRAINT dev_alias_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.device(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: device device_host_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device
    ADD CONSTRAINT device_host_id_fkey FOREIGN KEY (host_id) REFERENCES public.host(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20210526202613);
INSERT INTO public."schema_migrations" (version) VALUES (20211101114631);
INSERT INTO public."schema_migrations" (version) VALUES (20211129190841);
INSERT INTO public."schema_migrations" (version) VALUES (20220123142033);
