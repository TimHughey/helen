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
    name character varying(128) NOT NULL,
    device_id bigint,
    description character varying(50) DEFAULT '<none>'::character varying,
    cmd character varying(32) DEFAULT 'unknown'::character varying NOT NULL,
    pio integer NOT NULL,
    ttl_ms integer DEFAULT 60000 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
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
    cmd character varying(32) DEFAULT 'unknown'::character varying NOT NULL,
    alias_id bigint,
    refid character varying(8) NOT NULL,
    acked boolean DEFAULT false NOT NULL,
    orphaned boolean DEFAULT false NOT NULL,
    sent_at timestamp without time zone NOT NULL,
    acked_at timestamp without time zone,
    rt_latency_us integer DEFAULT 0
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
    ident character varying(128) NOT NULL,
    host character varying(128) NOT NULL,
    pios integer NOT NULL,
    latency_us integer DEFAULT 0,
    last_seen_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: pwm_device_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pwm_device_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pwm_device_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pwm_device_id_seq OWNED BY public.pwm_device.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


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

ALTER TABLE ONLY public.pwm_device ALTER COLUMN id SET DEFAULT nextval('public.pwm_device_id_seq'::regclass);


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
-- Name: pwm_device pwm_device_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pwm_device
    ADD CONSTRAINT pwm_device_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: pwm_alias_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_alias_name_index ON public.pwm_alias USING btree (name);


--
-- Name: pwm_cmd_refid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_cmd_refid_index ON public.pwm_cmd USING btree (refid);


--
-- Name: pwm_cmd_sent_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pwm_cmd_sent_at_index ON public.pwm_cmd USING brin (sent_at);


--
-- Name: pwm_device_ident_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pwm_device_ident_index ON public.pwm_device USING btree (ident);


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
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20210526202613);
