--------------------------------------------------------------------------------
-- crm_nl2sql_pkg.pkb  — Phase B (2026-07-04)
-- Xem header ở .pks. Trọng tâm an toàn: cột/toán tử/intent LẤY TỪ WHITELIST, giá
-- trị filter LUÔN bind qua DBMS_SQL. Không có nhánh nào execute chuỗi từ LLM.
--------------------------------------------------------------------------------
create or replace package body crm_nl2sql_pkg
as

  c_scope constant varchar2(30) := 'CRM_NL2SQL';

  c_refuse_msg constant varchar2(1000) :=
    'Xin lỗi, tôi chỉ TRA CỨU/THỐNG KÊ khách hàng tiềm năng (đếm, lọc, xếp hạng), '||
    'không thực hiện thêm/sửa/xoá dữ liệu và không trả lời ngoài phạm vi CRM_LEADS.';

  -- System prompt: NGẮN + CỐ ĐỊNH (byte-identical) để tái dùng KV-cache prefix.
  -- Không chèn ngày/user/session. Tiếng Việt có dấu.
  c_system_prompt constant clob :=
'Bạn chuyển câu hỏi tiếng Việt về khách hàng tiềm năng (bảng CRM_LEADS) thành JSON truy vấn. CHỈ trả JSON đúng schema, KHÔNG giải thích, KHÔNG viết SQL.'||chr(10)||
'intent: count=đếm số lượng; aggregate=thống kê/phân bố theo nhóm; list=liệt kê; rank=xếp hạng/top-N/cao nhất/thấp nhất.'||chr(10)||
'QUY TẮC CỘT LỌC (filters.col):'||chr(10)||
'- temperature = mức độ NÓNG/LẠNH. "nóng"->HOT, "ấm"->WARM, "nguội"/"lạnh"->COLD. LUÔN dùng temperature cho nóng/ấm/nguội, TUYỆT ĐỐI không dùng status.'||chr(10)||
'- status = giai đoạn: NEW, CONTACTED, QUALIFIED, IN_PROGRESS, DISQUALIFIED, WON, LOST. Chỉ dùng khi câu hỏi nhắc các từ này.'||chr(10)||
'- source = nguồn (Facebook, Zalo, Website...). emp_id = mã nhân viên (SỐ, vd 1001). score = điểm (SỐ).'||chr(10)||
'QUY TẮC group_by: MẶC ĐỊNH "none". Câu có "thống kê/phân bố/đếm ... theo/mỗi/từng <chiều>" thì LUÔN intent="aggregate" + group_by=<chiều> (KHÔNG dùng count, KHÔNG thêm filter cho chiều đó). "theo trạng thái"->status, "theo nguồn"->source, "theo mức độ nóng lạnh"->temperature. KHI ĐÃ group_by theo 1 cột thì TUYỆT ĐỐI KHÔNG thêm filter cho chính cột đó.'||chr(10)||
'Tên nguồn (Facebook, Zalo, Website, Google, Tiktok, Email, Hotline...) LUÔN thuộc cột source, KHÔNG BAO GIỜ thuộc status.'||chr(10)||
'QUY TẮC GIÁ TRỊ: filters.val PHẢI lấy đúng từ câu hỏi (emp_id=1001 nghĩa là val "1001"; điểm từ 80 nghĩa là val "80"). CẤM bịa giá trị. CẤM thêm filter có val rỗng/"none". Nếu không có giá trị lọc thì để filters rỗng [].'||chr(10)||
'sort_by/sort_dir chỉ dùng khi rank (mặc định score desc). limit=số dòng ("cao nhất"->1, "top 10"->10). Với list/rank nếu KHÔNG nêu số thì BỎ TRỐNG limit (đừng đặt 0).'||chr(10)||
'Nếu câu hỏi KHÔNG liên quan CRM_LEADS, hoặc yêu cầu THÊM/SỬA/XOÁ dữ liệu: trả {"intent":"refuse","filters":[]}.'||chr(10)||
'VÍ DỤ:'||chr(10)||
'"có bao nhiêu lead ở trạng thái NEW?" -> {"intent":"count","filters":[{"col":"status","op":"=","val":"NEW"}]}'||chr(10)||
'"đếm số lead nóng" -> {"intent":"count","filters":[{"col":"temperature","op":"=","val":"HOT"}]}'||chr(10)||
'"phân bố lead theo nguồn" -> {"intent":"aggregate","group_by":"source","filters":[]}'||chr(10)||
'"thống kê số lead theo trạng thái" -> {"intent":"aggregate","group_by":"status","filters":[]}'||chr(10)||
'"thống kê trạng thái của lead nguồn Zalo" -> {"intent":"aggregate","group_by":"status","filters":[{"col":"source","op":"=","val":"Zalo"}]}'||chr(10)||
'"lead nào điểm cao nhất?" -> {"intent":"rank","sort_by":"score","sort_dir":"desc","limit":1,"filters":[]}'||chr(10)||
'"top 5 lead điểm cao của nhân viên 1001" -> {"intent":"rank","sort_by":"score","sort_dir":"desc","limit":5,"filters":[{"col":"emp_id","op":"=","val":"1001"}]}'||chr(10)||
'"có bao nhiêu lead điểm từ 80 trở lên?" -> {"intent":"count","filters":[{"col":"score","op":">=","val":"80"}]}'||chr(10)||
'"có bao nhiêu lead theo từng mức độ nóng lạnh?" -> {"intent":"aggregate","group_by":"temperature","filters":[]}'||chr(10)||
'"liệt kê các lead nóng" -> {"intent":"list","filters":[{"col":"temperature","op":"=","val":"HOT"}]}'||chr(10)||
'"xóa hết lead LOST" -> {"intent":"refuse","filters":[]}';

  ------------------------------------------------------------------------------
  -- Whitelist metadata
  ------------------------------------------------------------------------------
  -- Cột lọc hợp lệ + kiểu (TRUE=text dùng bodau, FALSE=number)
  function is_text_col(p_col in varchar2) return boolean is
  begin
    return p_col in ('status','temperature','source');
  end;

  function is_num_col(p_col in varchar2) return boolean is
  begin
    return p_col in ('emp_id','score');
  end;

  function col_ok(p_col in varchar2) return boolean is
  begin
    return is_text_col(p_col) or is_num_col(p_col);
  end;

  function op_ok(p_op in varchar2) return boolean is
  begin
    return p_op in ('=','!=','>','>=','<','<=','LIKE');
  end;

  -- Guard TẤT ĐỊNH: câu hỏi chứa động từ sửa/xoá -> từ chối, KHÔNG cần gọi LLM.
  function is_dml_question(p_q in clob) return boolean is
    l_txt varchar2(2000);
    n     varchar2(2000);
  begin
    l_txt := dbms_lob.substr(p_q, 1900, 1);   -- CLOB -> VARCHAR2 an toàn
    n     := bodau(l_txt);                     -- UPPER + bỏ dấu
    return n like '%XOA%' or n like '%DELETE%' or n like '%DROP%'
        or n like '%TRUNCATE%' or n like '%CAP NHAT%' or n like '%UPDATE%'
        or n like '%SUA %' or n like '%INSERT%' or n like '%THEM MOI%'
        or n like '%ALTER%' or n like '%GHI DE%';
  end;

  function grp_expr(p_grp in varchar2) return varchar2 is
  begin
    -- TO_CHAR đồng nhất kiểu (tránh ORA-00932 như bug cũ Tool 3)
    case p_grp
      when 'status'      then return 'TO_CHAR(status)';
      when 'temperature' then return 'TO_CHAR(temperature)';
      when 'source'      then return 'TO_CHAR(source)';
      when 'emp_id'      then return 'TO_CHAR(emp_id)';
      else return null;
    end case;
  end;

  function sort_expr(p_sort in varchar2) return varchar2 is
  begin
    case p_sort
      when 'score'              then return 'score';
      when 'next_action_date'   then return 'next_action_date';
      when 'last_activity_date' then return 'last_activity_date';
      else return null;
    end case;
  end;

  ------------------------------------------------------------------------------
  -- JSON schema (PHẲNG, enum) cho Ollama structured output
  ------------------------------------------------------------------------------
  function build_schema return json_object_t is
    l_schema  json_object_t := json_object_t();
    l_props   json_object_t := json_object_t();
    l_req     json_array_t  := json_array_t();

    function enum_str(p_vals in varchar2) return json_object_t is
      l_o    json_object_t := json_object_t();
      l_a    json_array_t  := json_array_t();
      l_rest varchar2(4000) := p_vals;
      l_pos  pls_integer;
      l_tok  varchar2(200);
    begin
      loop
        l_pos := instr(l_rest, ',');
        if l_pos = 0 then
          l_tok := trim(l_rest); l_rest := null;
        else
          l_tok := trim(substr(l_rest, 1, l_pos-1));
          l_rest := substr(l_rest, l_pos+1);
        end if;
        if l_tok is not null then l_a.append(l_tok); end if;
        exit when l_rest is null;
      end loop;
      l_o.put('type','string');
      l_o.put('enum', l_a);
      return l_o;
    end;
  begin
    -- intent
    l_props.put('intent',  enum_str('count,aggregate,list,rank,refuse'));
    l_props.put('metric',  enum_str('none,count,avg_score,sum_score'));
    l_props.put('group_by',enum_str('none,status,temperature,source,emp_id'));
    l_props.put('sort_by', enum_str('none,score,next_action_date,last_activity_date'));
    l_props.put('sort_dir',enum_str('asc,desc'));

    -- filters: array of {col,op,val}
    declare
      l_fitem  json_object_t := json_object_t();
      l_fprops json_object_t := json_object_t();
      l_freq   json_array_t  := json_array_t();
      l_val    json_object_t := json_object_t();
      l_arr    json_object_t := json_object_t();
    begin
      l_fprops.put('col', enum_str('status,temperature,source,emp_id,score'));
      l_fprops.put('op',  enum_str('=,!=,>,>=,<,<=,LIKE'));
      l_val.put('type','string'); l_fprops.put('val', l_val);
      l_freq.append('col'); l_freq.append('op'); l_freq.append('val');
      l_fitem.put('type','object');
      l_fitem.put('properties', l_fprops);
      l_fitem.put('required', l_freq);
      l_arr.put('type','array');
      l_arr.put('items', l_fitem);
      l_props.put('filters', l_arr);
    end;

    -- limit
    declare l_lim json_object_t := json_object_t();
    begin l_lim.put('type','integer'); l_props.put('limit', l_lim); end;

    l_schema.put('type','object');
    l_schema.put('properties', l_props);
    l_req.append('intent'); l_req.append('filters');
    l_schema.put('required', l_req);
    return l_schema;
  end build_schema;

  ------------------------------------------------------------------------------
  -- Gọi LLM (1 call) -> trả json_object_t intent
  ------------------------------------------------------------------------------
  function get_intent_json(p_question in clob) return json_object_t is
    l_res  json_object_t;
    l_raw  clob;
  begin
    uc_ai.g_base_url                   := g_base_url;
    uc_ai_ollama.g_apex_web_credential := g_web_credential;
    uc_ai_ollama.g_use_responses_api   := false;

    l_res := uc_ai.generate_text(
               p_user_prompt          => p_question,
               p_system_prompt        => c_system_prompt,
               p_provider             => uc_ai.c_provider_ollama,
               p_model                => g_model,
               p_max_tool_calls       => 1,               -- không tool -> vẫn 1 call
               p_response_json_schema => build_schema());

    l_raw := l_res.get_clob('final_message');
    if l_raw is null then
      raise_application_error(-20951, 'CRM_NL2SQL: LLM tra ve rong.');
    end if;
    return json_object_t(l_raw);
  exception
    when others then
      if sqlcode = -20951 then raise; end if;
      raise_application_error(-20952,
        'CRM_NL2SQL: khong parse duoc JSON intent tu LLM: '||substr(sqlerrm,1,200));
  end get_intent_json;

  ------------------------------------------------------------------------------
  -- Dựng WHERE (whitelist) + thu thập bind. Trả WHERE text; OUT hai mảng bind.
  ------------------------------------------------------------------------------
  procedure build_where(
    p_j        in  json_object_t,
    p_group    in  varchar2,          -- cột đang group_by ('none' nếu không) — để bỏ filter trùng
    p_where    out varchar2,
    p_names    out sys.odcivarchar2list,
    p_vals     out sys.odcivarchar2list,
    p_isnum    out sys.odcinumberlist)
  is
    l_filters json_array_t;
    l_f       json_object_t;
    l_col     varchar2(30);
    l_op      varchar2(4);
    l_val     varchar2(4000);
    l_w       varchar2(8000) := ' WHERE 1=1';
    l_bn      varchar2(20);
    l_i       pls_integer := 0;
    l_n       varchar2(400);
  begin
    p_names := sys.odcivarchar2list();
    p_vals  := sys.odcivarchar2list();
    p_isnum := sys.odcinumberlist();

    if not p_j.has('filters') then p_where := l_w; return; end if;
    l_filters := p_j.get_array('filters');

    for k in 0 .. l_filters.get_size - 1 loop
      exit when l_i >= 6;                       -- cap 6 filter
      l_f   := treat(l_filters.get(k) as json_object_t);
      l_col := lower(l_f.get_string('col'));
      l_op  := upper(l_f.get_string('op'));
      l_val := l_f.get_string('val');

      if not col_ok(l_col) then
        raise_application_error(-20953,'CRM_NL2SQL: cot ngoai whitelist: '||l_col);
      end if;
      if not op_ok(l_op) then
        raise_application_error(-20954,'CRM_NL2SQL: toan tu ngoai whitelist: '||l_op);
      end if;
      if l_op = 'LIKE' and not is_text_col(l_col) then
        raise_application_error(-20955,'CRM_NL2SQL: LIKE chi cho cot text');
      end if;
      if l_val is null then continue; end if;

      -- Chuẩn hoá nhiệt độ + TỰ SỬA cột: model yếu hay để "nóng/ấm/nguội" vào
      -- status. Nếu val là từ chỉ nhiệt độ -> ép col='temperature' + val canonical.
      l_n := bodau(l_val);   -- UPPER + bỏ dấu
      if l_n in ('NONG','HOT') then
        l_col := 'temperature'; l_val := 'HOT';
      elsif l_n in ('AM','WARM') then
        l_col := 'temperature'; l_val := 'WARM';
      elsif l_n in ('NGUOI','LANH','COLD') then
        l_col := 'temperature'; l_val := 'COLD';
      elsif l_col <> 'source'
            and l_n in ('FACEBOOK','ZALO','WEBSITE','GOOGLE','TIKTOK','EMAIL',
                        'HOTLINE','FANPAGE','FORM','LANDING PAGE','GIOI THIEU',
                        'REFERRAL','ADS','QUANG CAO') then
        -- model hay để tên NGUỒN vào nhầm cột status -> ép về source
        l_col := 'source';
      end if;
      -- BỎ filter rác của model yếu (CONTINUE ở cấp loop, không lồng block):
      --  (1) val sentinel none/null;  (2) filter trùng cột đang group_by
      --      (Q6: group_by=temperature + 3 filter temperature mâu thuẫn -> 0 dòng).
      if l_n in ('NONE','NULL') then continue; end if;
      if p_group is not null and l_col = p_group then continue; end if;

      l_bn := ':b'||l_i;
      if is_text_col(l_col) then
        if l_op = 'LIKE' then
          l_w := l_w||' AND bodau('||l_col||') LIKE ''%''||bodau('||l_bn||')||''%''';
        else
          l_w := l_w||' AND bodau('||l_col||') '||l_op||' bodau('||l_bn||')';
        end if;
        p_names.extend; p_names(p_names.count) := ':b'||l_i;
        p_vals.extend;  p_vals(p_vals.count)   := l_val;
        p_isnum.extend; p_isnum(p_isnum.count) := 0;
      else -- numeric
        l_w := l_w||' AND '||l_col||' '||l_op||' '||l_bn;
        p_names.extend; p_names(p_names.count) := ':b'||l_i;
        p_vals.extend;  p_vals(p_vals.count)   := l_val;   -- validate số ở exec
        p_isnum.extend; p_isnum(p_isnum.count) := 1;
      end if;
      l_i := l_i + 1;
    end loop;

    p_where := l_w;
  end build_where;

  ------------------------------------------------------------------------------
  -- Dựng câu SELECT hoàn chỉnh theo intent (chỉ token whitelist + :b*)
  ------------------------------------------------------------------------------
  function build_sql(p_j in json_object_t, p_where in varchar2) return varchar2 is
    l_intent varchar2(20) := lower(nvl(p_j.get_string('intent'),'list'));
    l_grp    varchar2(20);
    l_sortby varchar2(30);
    l_dir    varchar2(4);
    l_lim    pls_integer;
    l_sql    varchar2(16000);
  begin
    if p_j.has('group_by') then l_grp := lower(p_j.get_string('group_by')); end if;
    if p_j.has('sort_by')  then l_sortby := lower(p_j.get_string('sort_by')); end if;
    l_dir := lower(nvl(p_j.get_string('sort_dir'),'desc'));
    if l_dir not in ('asc','desc') then l_dir := 'desc'; end if;
    begin l_lim := p_j.get_number('limit'); exception when others then l_lim := null; end;
    -- limit<=0 hoặc null -> dùng cap (model yếu hay để limit:0 cho câu list/rank).
    if l_lim is null or l_lim <= 0 then l_lim := g_row_cap; end if;
    if l_lim > g_row_cap then l_lim := g_row_cap; end if;

    if l_intent = 'count' and (l_grp is null or l_grp = 'none') then
      l_sql := 'SELECT COUNT(*) AS cnt FROM CRM_LEADS'||p_where;

    elsif l_intent in ('aggregate','count') and grp_expr(l_grp) is not null then
      l_sql := 'SELECT '||grp_expr(l_grp)||' AS group_value, COUNT(*) AS cnt,'||
               ' ROUND(AVG(score),2) AS avg_score, SUM(score) AS sum_score'||
               ' FROM CRM_LEADS'||p_where||
               ' GROUP BY '||grp_expr(l_grp)||' ORDER BY cnt DESC'||
               ' FETCH FIRST '||g_row_cap||' ROWS ONLY';

    else -- list / rank
      l_sql := 'SELECT cle_code, cle_name, customer, status, temperature,'||
               ' score, owner FROM CRM_LEADS'||p_where;
      if l_intent = 'rank' and sort_expr(l_sortby) is not null then
        l_sql := l_sql||' ORDER BY '||sort_expr(l_sortby)||' '||l_dir||' NULLS LAST';
      else
        l_sql := l_sql||' ORDER BY score DESC NULLS LAST';
      end if;
      l_sql := l_sql||' FETCH FIRST '||l_lim||' ROWS ONLY';
    end if;

    return l_sql;
  end build_sql;

  ------------------------------------------------------------------------------
  -- Chạy SQL bằng DBMS_SQL (bind theo tên) + format CLOB tiếng Việt
  ------------------------------------------------------------------------------
  function run_sql(
    p_sql   in varchar2,
    p_names in sys.odcivarchar2list,
    p_vals  in sys.odcivarchar2list,
    p_isnum in sys.odcinumberlist,
    p_shape in varchar2) return clob
  is
    l_c    integer := dbms_sql.open_cursor;
    l_n    integer;
    l_out  clob;
    -- buffers
    l_cnt  number;
    l_gv   varchar2(400); l_avg number; l_sum number;
    l_code varchar2(100); l_name varchar2(400); l_cust varchar2(400);
    l_st   varchar2(100); l_temp varchar2(100); l_score number; l_owner varchar2(100);
    l_rows pls_integer := 0;
  begin
    dbms_sql.parse(l_c, p_sql, dbms_sql.native);

    for i in 1 .. p_names.count loop
      if p_isnum(i) = 1 then
        begin
          dbms_sql.bind_variable(l_c, p_names(i), to_number(p_vals(i)));
        exception when others then
          dbms_sql.close_cursor(l_c);
          raise_application_error(-20956,'CRM_NL2SQL: gia tri so khong hop le: '||p_vals(i));
        end;
      else
        dbms_sql.bind_variable(l_c, p_names(i), p_vals(i));
      end if;
    end loop;

    if p_shape = 'count' then
      dbms_sql.define_column(l_c, 1, l_cnt);
      l_n := dbms_sql.execute_and_fetch(l_c);
      dbms_sql.column_value(l_c, 1, l_cnt);
      l_out := 'Kết quả: ' || l_cnt || ' lead.';

    elsif p_shape = 'aggregate' then
      dbms_sql.define_column(l_c, 1, l_gv, 400);
      dbms_sql.define_column(l_c, 2, l_cnt);
      dbms_sql.define_column(l_c, 3, l_avg);
      dbms_sql.define_column(l_c, 4, l_sum);
      l_n := dbms_sql.execute(l_c);
      l_out := 'Thống kê (nhóm | số lượng | điểm TB | tổng điểm):'||chr(10);
      loop
        exit when dbms_sql.fetch_rows(l_c) = 0;
        dbms_sql.column_value(l_c,1,l_gv);
        dbms_sql.column_value(l_c,2,l_cnt);
        dbms_sql.column_value(l_c,3,l_avg);
        dbms_sql.column_value(l_c,4,l_sum);
        l_out := l_out||'- '||nvl(l_gv,'(tat ca)')||': '||l_cnt||
                 ' | '||nvl(to_char(l_avg),'-')||' | '||nvl(to_char(l_sum),'-')||chr(10);
        l_rows := l_rows + 1;
      end loop;
      if l_rows = 0 then l_out := l_out||'(khong co du lieu)'; end if;

    else -- list / rank
      dbms_sql.define_column(l_c, 1, l_code, 100);
      dbms_sql.define_column(l_c, 2, l_name, 400);
      dbms_sql.define_column(l_c, 3, l_cust, 400);
      dbms_sql.define_column(l_c, 4, l_st, 100);
      dbms_sql.define_column(l_c, 5, l_temp, 100);
      dbms_sql.define_column(l_c, 6, l_score);
      dbms_sql.define_column(l_c, 7, l_owner, 100);
      l_n := dbms_sql.execute(l_c);
      l_out := 'Danh sách lead (mã | tên | KH | trạng thái | nhiệt | điểm | phụ trách):'||chr(10);
      loop
        exit when dbms_sql.fetch_rows(l_c) = 0;
        dbms_sql.column_value(l_c,1,l_code); dbms_sql.column_value(l_c,2,l_name);
        dbms_sql.column_value(l_c,3,l_cust); dbms_sql.column_value(l_c,4,l_st);
        dbms_sql.column_value(l_c,5,l_temp); dbms_sql.column_value(l_c,6,l_score);
        dbms_sql.column_value(l_c,7,l_owner);
        l_out := l_out||'- '||l_code||' | '||l_name||' | '||nvl(l_cust,'-')||' | '||
                 nvl(l_st,'-')||' | '||nvl(l_temp,'-')||' | '||nvl(to_char(l_score),'-')||
                 ' | '||nvl(l_owner,'-')||chr(10);
        l_rows := l_rows + 1;
      end loop;
      if l_rows = 0 then l_out := l_out||'(khong tim thay lead phu hop)'; end if;
    end if;

    dbms_sql.close_cursor(l_c);
    return l_out;
  exception
    when others then
      if dbms_sql.is_open(l_c) then dbms_sql.close_cursor(l_c); end if;
      raise;
  end run_sql;

  ------------------------------------------------------------------------------
  -- shape từ intent (để chọn define_column set)
  ------------------------------------------------------------------------------
  function shape_of(p_j in json_object_t) return varchar2 is
    l_intent varchar2(20) := lower(nvl(p_j.get_string('intent'),'list'));
    l_grp    varchar2(20) := lower(nvl(p_j.get_string('group_by'),'none'));
  begin
    if l_intent = 'count' and l_grp = 'none' then return 'count'; end if;
    if l_intent in ('aggregate','count') and grp_expr(l_grp) is not null then return 'aggregate'; end if;
    return 'list';
  end;

  ------------------------------------------------------------------------------
  -- PUBLIC
  ------------------------------------------------------------------------------
  function build_only(p_question in clob) return clob is
    l_j     json_object_t;
    l_grp   varchar2(20);
    l_where varchar2(8000);
    l_names sys.odcivarchar2list;
    l_vals  sys.odcivarchar2list;
    l_isnum sys.odcinumberlist;
    l_sql   varchar2(16000);
  begin
    if is_dml_question(p_question) then
      return 'INTENT_JSON: {"intent":"refuse"} (guard DML) SQL: (khong chay)';
    end if;
    l_j := get_intent_json(p_question);
    if lower(nvl(l_j.get_string('intent'),'list')) = 'refuse' then
      return 'INTENT_JSON: '||l_j.to_clob()||' SQL: (khong chay - refuse)';
    end if;
    l_grp := lower(nvl(l_j.get_string('group_by'),'none'));
    build_where(l_j, l_grp, l_where, l_names, l_vals, l_isnum);
    l_sql := build_sql(l_j, l_where);
    return 'INTENT_JSON: '||l_j.to_clob()||chr(10)||'SQL: '||l_sql;
  end build_only;

  function ask(p_question in clob, p_debug in boolean default false) return clob is
    l_j     json_object_t;
    l_grp   varchar2(20);
    l_where varchar2(8000);
    l_names sys.odcivarchar2list;
    l_vals  sys.odcivarchar2list;
    l_isnum sys.odcinumberlist;
    l_sql   varchar2(16000);
    l_ans   clob;
  begin
    if is_dml_question(p_question) then
      return c_refuse_msg;
    end if;
    l_j := get_intent_json(p_question);
    if lower(nvl(l_j.get_string('intent'),'list')) = 'refuse' then
      return c_refuse_msg;
    end if;
    l_grp := lower(nvl(l_j.get_string('group_by'),'none'));
    build_where(l_j, l_grp, l_where, l_names, l_vals, l_isnum);
    l_sql := build_sql(l_j, l_where);
    l_ans := run_sql(l_sql, l_names, l_vals, l_isnum, shape_of(l_j));
    if p_debug then
      l_ans := l_ans||chr(10)||chr(10)||'[DEBUG] INTENT: '||l_j.to_clob()||chr(10)||'[DEBUG] SQL: '||l_sql;
    end if;
    return l_ans;
  end ask;

end crm_nl2sql_pkg;
/
