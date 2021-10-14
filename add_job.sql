--
-- pgagent.add_job - simple SQL API for creating job/step/schedule
--

DROP FUNCTION IF EXISTS pgagent.remove_job;
CREATE FUNCTION pgagent.remove_job (
  _jobname	text
)
RETURNS VOID
LANGUAGE SQL AS
$pgagent$
	/* Allow DELETE CASCADE to do our work for us */
	DELETE FROM pgagent.pga_job WHERE jobname = _jobname;
$pgagent$;

DROP FUNCTION IF EXISTS pgagent.add_job;
CREATE FUNCTION pgagent.add_job (
  _jobname	text
, _jobsched	text
, _jobtask	text
, _jobkind	text default 'sql'
, _jobclass text default 'Miscellaneous'
)
RETURNS VOID
LANGUAGE PLPGSQL AS
$pgagent$
DECLARE
  jid		integer;
  scid		integer;
  jobclass	integer;
  jobstepkind	char(1);
  jobdbname		text := '';
  jobconnstr	text := '';
  tmpsched  text;

  /* Schedule data to match pgagent definitions */
  schedmins bool[60] := '{' || repeat('f,', 59) || 'f}';
  schedhrs	bool[24] := '{' || repeat('f,', 23) || 'f}';
  schedmday bool[32] := '{' || repeat('f,', 31) || 'f}';
  schedmth  bool[12] := '{' || repeat('f,', 11) || 'f}';
  schedwday	bool[7]  := '{' || repeat('f,', 6) || 'f}';

BEGIN

--validate cron schedule
IF (split_part(_jobsched, ' ', 5) IS NULL) THEN
	RAISE NOTICE 'pagent.add_job: invalid schedule - must have at least 5 parts';
END IF;

tmpsched := split_part(_jobsched, ' ', 1);
IF (tmpsched != '*') THEN
	IF (tmpsched !~ '[1-5][1-9]|[0-9]') THEN
		RAISE NOTICE 'pagent.add_job: invalid input for minutes, part 1, of %', _jobsched;
	END IF;
	schedmins[tmpsched::integer] := true;
END IF;

tmpsched := split_part(_jobsched, ' ', 2);
IF (tmpsched != '*') THEN
	IF (tmpsched !~ '[1-2][1-9]|[0-9]') THEN
		RAISE NOTICE 'pagent.add_job: invalid input for minutes, part 1, of %', _jobsched;
	END IF;
	IF (tmpsched::integer < 0 OR tmpsched::integer > 23) THEN
		RAISE NOTICE 'pagent.add_job: hours out of range';
	END IF;
	-- Add +1 so that first element corresponds to hour 0
	schedhrs[tmpsched::integer + 1] := true;
END IF;

tmpsched := split_part(_jobsched, ' ', 3);
IF (tmpsched != '*') THEN
	IF (tmpsched::integer < 1 OR tmpsched::integer > 31) THEN
		RAISE NOTICE 'pagent.add_job: days of month out of range';
	END IF;
	schedmday[tmpsched::integer] := true;
END IF;

tmpsched := split_part(_jobsched, ' ', 4);
IF (tmpsched != '*') THEN
	IF (tmpsched::integer < 1 OR tmpsched::integer > 12) THEN
		RAISE NOTICE 'pagent.add_job: month out of range';
	END IF;
	schedmth[tmpsched::integer] := true;
END IF;

tmpsched := split_part(_jobsched, ' ', 5);
IF (tmpsched != '*') THEN
	IF (tmpsched::integer < 1 OR tmpsched::integer > 7) THEN
		RAISE NOTICE 'pagent.add_job: days of week out of range';
	END IF;
	schedwday[tmpsched::integer] := true;
END IF;

--validate jobclass
SELECT jclid INTO jobclass FROM pgagent.pga_jobclass WHERE jclname = _jobclass;
IF NOT FOUND THEN
  SELECT jclid INTO jobclass FROM pgagent.pga_jobclass WHERE jclname = 'Miscellaneous';
END IF;

--create job
INSERT INTO pgagent.pga_job (
 jobjclid, jobname
) VALUES (
 jobclass
,_jobname
) RETURNING jobid INTO jid;

--validate job step kind
IF (_jobkind = 'sql') THEN
  jobstepkind = 's';
ELSIF (_jobkind = 's') THEN
  jobstepkind = 's';
ELSIF (_jobkind = 'batch' ) THEN
  jobstepkind = 'b';
ELSIF (_jobkind = 'b' ) THEN
  jobstepkind = 'b';
ELSE
  RAISE NOTICE 'Unknown kind of job step';
END IF;

IF (jobstepkind = 'b') THEN
  jobdbname = current_database();
ELSE
  jobconnstr = coalesce(current_setting('pgagent.default_connstr', true), 'localhost');
END IF;

--create step
INSERT INTO pgagent.pga_jobstep (
 jstjobid, jstname, jstkind, jstonerror, jstcode, jstdbname, jstconnstr
) VALUES (
 jid
,_jobname || '_step1'
,jobstepkind
,'f'
,_jobtask
,jobdbname
,jobconnstr
);

--create schedule
INSERT INTO pgagent.pga_schedule (
 jscjobid, jscname, jscminutes, jschours, jscmonthdays, jscmonths, jscweekdays
) VALUES (
 jid
,_jobname || '_sched1'
,schedmins
,schedhrs
,schedmday
,schedmth
,schedwday
);

END;
$pgagent$;

SET pgagent.default_connstr = 'localhost';

SELECT pgagent.remove_job('reindex');
SELECT pgagent.add_job('reindex', '15 0 * * *', 'reindex database postgres');
SELECT pgagent.remove_job('reindex2');
SELECT pgagent.add_job('reindex2', '30 1 * * 7', 'reindex (concurrently) database postgres');

select * from pgagent.pga_job;
select * from pgagent.pga_jobstep;
select * from pgagent.pga_schedule;
