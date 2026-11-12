-- InvoiceFlow v4 migration: run once after v3 migration.
create table if not exists public.business_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  dana_number text,
  dana_holder text,
  bca_number text,
  bca_holder text,
  updated_at timestamptz not null default now()
);
alter table public.business_profiles add column if not exists dana_holder text;
alter table public.business_profiles enable row level security;
drop policy if exists "business_profiles_select_own" on public.business_profiles;
create policy "business_profiles_select_own" on public.business_profiles for select to authenticated using (auth.uid()=user_id);
drop policy if exists "business_profiles_insert_own" on public.business_profiles;
create policy "business_profiles_insert_own" on public.business_profiles for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "business_profiles_update_own" on public.business_profiles;
create policy "business_profiles_update_own" on public.business_profiles for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);

alter table public.invoices add column if not exists paid_at date;
update public.invoices set paid_at=invoice_date where status='Paid' and paid_at is null;
update public.invoices set paid_at=null where status<>'Paid' and paid_at is not null;

create or replace function public.create_invoice(
 p_customer_id uuid,p_seller_name text,p_seller_contact text,p_invoice_date date,p_due_date date,
 p_status text,p_notes text,p_discount numeric,p_customer_snapshot jsonb,p_items jsonb
) returns uuid language plpgsql security invoker set search_path=public as $$
declare
 v_user uuid:=auth.uid(); v_year integer:=extract(year from p_invoice_date)::integer;
 v_next integer; v_number text; v_invoice_id uuid;
 v_subtotal numeric(14,2); v_discount numeric(14,2); v_total numeric(14,2);
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_status not in ('Paid','Unpaid') then raise exception 'Invalid payment status'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required'; end if;
 if not exists(select 1 from public.customers c where c.id=p_customer_id and c.user_id=v_user) then raise exception 'Customer not found or access denied'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) item where coalesce(trim(item->>'description'),'')='' or coalesce((item->>'quantity')::numeric,0)<=0 or coalesce((item->>'unit_price')::numeric,-1)<0) then raise exception 'Invalid invoice item'; end if;
 select coalesce(sum((item->>'quantity')::numeric*(item->>'unit_price')::numeric),0) into v_subtotal from jsonb_array_elements(p_items) item;
 v_discount:=greatest(coalesce(p_discount,0),0);
 if v_discount>v_subtotal then raise exception 'Discount cannot exceed subtotal'; end if;
 v_total:=v_subtotal-v_discount;
 insert into public.invoice_counters(user_id,invoice_year,last_number) values(v_user,v_year,1)
 on conflict(user_id,invoice_year) do update set last_number=public.invoice_counters.last_number+1 returning last_number into v_next;
 v_number:='INV/'||v_year::text||'/'||lpad(v_next::text,3,'0');
 insert into public.invoices(user_id,customer_id,invoice_number,seller_name,seller_contact,invoice_date,due_date,status,paid_at,notes,subtotal,discount,total,customer_snapshot)
 values(v_user,p_customer_id,v_number,p_seller_name,p_seller_contact,p_invoice_date,p_due_date,p_status,
 case when p_status='Paid' then current_date else null end,p_notes,v_subtotal,v_discount,v_total,coalesce(p_customer_snapshot,'{}'::jsonb))
 returning id into v_invoice_id;
 insert into public.invoice_items(invoice_id,description,quantity,unit_price)
 select v_invoice_id,item->>'description',(item->>'quantity')::numeric,(item->>'unit_price')::numeric from jsonb_array_elements(p_items) item;
 return v_invoice_id;
end; $$;

create or replace function public.update_invoice(
 p_invoice_id uuid,p_customer_id uuid,p_seller_name text,p_seller_contact text,p_invoice_date date,p_due_date date,
 p_status text,p_notes text,p_discount numeric,p_customer_snapshot jsonb,p_items jsonb
) returns void language plpgsql security invoker set search_path=public as $$
declare
 v_user uuid:=auth.uid(); v_subtotal numeric(14,2); v_discount numeric(14,2); v_total numeric(14,2);
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_status not in ('Paid','Unpaid') then raise exception 'Invalid payment status'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required'; end if;
 if not exists(select 1 from public.customers c where c.id=p_customer_id and c.user_id=v_user) then raise exception 'Customer not found or access denied'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) item where coalesce(trim(item->>'description'),'')='' or coalesce((item->>'quantity')::numeric,0)<=0 or coalesce((item->>'unit_price')::numeric,-1)<0) then raise exception 'Invalid invoice item'; end if;
 select coalesce(sum((item->>'quantity')::numeric*(item->>'unit_price')::numeric),0) into v_subtotal from jsonb_array_elements(p_items) item;
 v_discount:=greatest(coalesce(p_discount,0),0);
 if v_discount>v_subtotal then raise exception 'Discount cannot exceed subtotal'; end if;
 v_total:=v_subtotal-v_discount;
 update public.invoices set customer_id=p_customer_id,seller_name=p_seller_name,seller_contact=p_seller_contact,
 invoice_date=p_invoice_date,due_date=p_due_date,status=p_status,
 paid_at=case when p_status='Paid' then coalesce(paid_at,current_date) else null end,
 notes=p_notes,subtotal=v_subtotal,discount=v_discount,total=v_total,customer_snapshot=coalesce(p_customer_snapshot,'{}'::jsonb)
 where id=p_invoice_id and user_id=v_user;
 if not found then raise exception 'Invoice not found or access denied'; end if;
 delete from public.invoice_items where invoice_id=p_invoice_id;
 insert into public.invoice_items(invoice_id,description,quantity,unit_price)
 select p_invoice_id,item->>'description',(item->>'quantity')::numeric,(item->>'unit_price')::numeric from jsonb_array_elements(p_items) item;
end; $$;
grant execute on function public.create_invoice(uuid,text,text,date,date,text,text,numeric,jsonb,jsonb) to authenticated;
grant execute on function public.update_invoice(uuid,uuid,text,text,date,date,text,text,numeric,jsonb,jsonb) to authenticated;
