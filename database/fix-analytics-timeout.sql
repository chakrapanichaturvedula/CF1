-- ============================================================================
-- Fix: "Load failed: canceling statement due to statement timeout" on
-- faculty.html.
--
-- Cause 1. v_page_coverage matched progress rows to a section with a
--   correlated "student_id in (select ... where section_id = r.section_id)"
--   inside the join. Postgres re-ran it for every page and section, and the
--   row-level rule on progress called app.can_see_student() once per row.
--   With a full roster this takes minutes; Supabase stops queries at 8 s.
-- Cause 2. The access rules called the helper functions once per row.
--   Wrapping them as (select ...) lets Postgres run them once per query.
--
-- Safe to run more than once. Paste the whole file into the Supabase SQL
-- editor and press Run. No data is changed.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. One list of the students the signed-in person may see, computed once.
-- ----------------------------------------------------------------------------
create or replace function app.my_visible_student_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select st.id from public.students st
  where app.is_in_charge()
     or st.section_id in (select app.my_section_ids())
  union
  select l.student_id from public.student_links l where l.auth_uid = auth.uid()
$$;
grant execute on function app.my_visible_student_ids() to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Access rules rewritten so each helper runs once per query.
--    Who can see what is unchanged.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['offerings','sections','students','staff','staff_sections',
                           'content_items','content_visibility','activities',
                           'participation_weights'] loop
    execute format('drop policy if exists incharge_all on public.%I', t);
    execute format('create policy incharge_all on public.%I for all to authenticated
                    using ((select app.is_in_charge())) with check ((select app.is_in_charge()))', t);
  end loop;

  foreach t in array array['offerings','content_items','content_visibility',
                           'activities','participation_weights'] loop
    execute format('drop policy if exists staff_read on public.%I', t);
    execute format('create policy staff_read on public.%I for select to authenticated
                    using ((select app.is_staff()))', t);
  end loop;
end $$;

drop policy if exists incharge_read on public.archive_item_stats;
create policy incharge_read on public.archive_item_stats for select to authenticated
  using ((select app.is_in_charge()));

drop policy if exists own_row on public.staff;
create policy own_row on public.staff for select to authenticated
  using (email = (select app.jwt_email()));
drop policy if exists own_row on public.staff_sections;
create policy own_row on public.staff_sections for select to authenticated
  using (staff_email = (select app.jwt_email()));

drop policy if exists scoped_read on public.students;
create policy scoped_read on public.students for select to authenticated
  using (id in (select app.my_visible_student_ids()));
drop policy if exists scoped_read on public.progress;
create policy scoped_read on public.progress for select to authenticated
  using (student_id in (select app.my_visible_student_ids()));
drop policy if exists scoped_read on public.attempts;
create policy scoped_read on public.attempts for select to authenticated
  using (student_id in (select app.my_visible_student_ids()));
drop policy if exists scoped_read on public.claim_log;
create policy scoped_read on public.claim_log for select to authenticated
  using (student_id in (select app.my_visible_student_ids()));

-- ----------------------------------------------------------------------------
-- 3. Analytics views: totals computed once per section or student, then
--    joined, instead of a sub-query per row. Same columns as before.
-- ----------------------------------------------------------------------------
create or replace view public.v_page_coverage with (security_invoker = true) as
with sec_progress as (
  select st.section_id, p.item_id,
         count(*) as started,
         count(*) filter (where p.status = 'completed') as completed,
         round(avg(p.active_seconds) / 60.0, 1) as avg_active_minutes
  from public.progress p
  join public.students st on st.id = p.student_id
  group by st.section_id, p.item_id
),
sec_size as (
  select section_id, count(*) as students
  from public.students group by section_id
)
select
  r.offering_id,
  sec.name as section,
  ci.slug,
  ci.title,
  ci.sort,
  r.released,
  coalesce(ss.students, 0)  as students,
  coalesce(sp.started, 0)   as started,
  coalesce(sp.completed, 0) as completed,
  sp.avg_active_minutes
from public.v_item_release r
join public.sections sec on sec.id = r.section_id
join public.content_items ci on ci.id = r.item_id and ci.kind = 'page'
left join sec_progress sp on sp.section_id = r.section_id and sp.item_id = r.item_id
left join sec_size ss on ss.section_id = r.section_id;

create or replace view public.v_student_overview with (security_invoker = true) as
with released as (
  select r.offering_id, r.section_id, count(*) as pages_released
  from public.v_item_release r
  join public.content_items ci on ci.id = r.item_id and ci.kind = 'page'
  where r.released
  group by r.offering_id, r.section_id
),
prog as (
  select student_id,
         count(*) as pages_started,
         count(*) filter (where status = 'completed') as pages_completed,
         round(sum(active_seconds) / 60.0, 1) as active_minutes,
         max(last_seen_at) as last_active_at
  from public.progress group by student_id
),
att as (
  select student_id, count(*) as attempts from public.attempts group by student_id
),
dev as (
  select student_id, count(distinct auth_uid) as devices
  from public.claim_log where success group by student_id
)
select
  st.id as student_id,
  st.offering_id,
  st.section_id,
  sec.name as section,
  st.student_code,
  st.full_name,
  coalesce(rel.pages_released, 0)   as pages_released,
  coalesce(pr.pages_started, 0)     as pages_started,
  coalesce(pr.pages_completed, 0)   as pages_completed,
  coalesce(pr.active_minutes, 0)    as active_minutes,
  pr.last_active_at,
  coalesce(at.attempts, 0)          as attempts,
  coalesce(dv.devices, 0)           as devices
from public.students st
join public.sections sec on sec.id = st.section_id
left join released rel on rel.offering_id = st.offering_id and rel.section_id = st.section_id
left join prog pr on pr.student_id = st.id
left join att  at on at.student_id = st.id
left join dev  dv on dv.student_id = st.id;

-- Helpful index for per-page totals.
create index if not exists progress_item_idx on public.progress (item_id);

commit;
