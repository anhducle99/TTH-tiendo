begin;

-- Không chỉ ẩn lựa chọn trên giao diện: mọi đường ghi dữ liệu đều phải
-- có lượt nộp và bằng chứng hợp lệ trước khi vào Chờ duyệt/Hoàn thành.
create or replace function public.validate_work_item_completion_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  latest_request_status public.completion_request_status;
begin
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status then return new; end if;
  end if;

  select request.status into latest_request_status
  from public.completion_requests request
  where request.work_item_id = new.id
  order by request.attempt_no desc
  limit 1;

  if new.status in ('pending_approval', 'completed') then
    if (select count(*) from public.attachments attachment where attachment.work_item_id = new.id) <> 1 then
      raise exception 'Phải tải đúng một bằng chứng và bấm nộp trước khi hoàn thành công việc';
    end if;
    if new.status = 'pending_approval' and latest_request_status is distinct from 'pending'::public.completion_request_status then
      raise exception 'Phải bấm nộp để gửi công việc cho quản trị viên duyệt';
    end if;
    if new.status = 'completed' and latest_request_status is distinct from 'approved'::public.completion_request_status then
      raise exception 'Công việc chỉ hoàn thành sau khi nộp và được duyệt hợp lệ';
    end if;
  elsif tg_op = 'UPDATE' then
    if old.status in ('pending_approval', 'completed')
      and latest_request_status is distinct from 'rejected'::public.completion_request_status then
      raise exception 'Không đổi trực tiếp trạng thái đã nộp; bằng chứng vẫn được khóa. Việc chờ duyệt phải được xét duyệt hoặc từ chối';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists work_items_01_validate_completion_transition on public.work_items;
create trigger work_items_01_validate_completion_transition
before insert or update on public.work_items
for each row execute function public.validate_work_item_completion_transition();

revoke execute on function public.validate_work_item_completion_transition() from public, anon, authenticated;

commit;
