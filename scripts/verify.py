#!/usr/bin/env python3
"""Real-process checks for the CLI, shared persistence and MCP stdio transport."""
import json
import pathlib
import selectors
import subprocess
import tempfile
import sys

ROOT=pathlib.Path(__file__).resolve().parents[1]
BIN=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/"build/知间.app/Contents/MacOS/zhijian"

with tempfile.TemporaryDirectory(prefix="zhijian-verify-") as folder:
    directory=pathlib.Path(folder)
    database=directory/"library.sqlite"
    def cli(*args, payload=None, ok=True, db=database):
        result=subprocess.run([str(BIN),"--database",str(db),"--no-seed",*map(str,args)],input=None if payload is None else json.dumps(payload,ensure_ascii=False),text=True,capture_output=True,timeout=30)
        if (result.returncode==0)!=ok: raise AssertionError((args,result.stdout,result.stderr))
        return json.loads(result.stdout)

    entry=cli("create","--json","-",payload={"title":"主干传送带","english":"Residual Stream","summary":"贯穿模型各层的共享表示","personalNote":"我的原创理解"})
    eid=entry["id"]
    assert cli("get",eid)["content"]["personalNote"]=="我的原创理解"
    assert cli("list","--query","Stream")["total"]==1
    changed=cli("update",eid,"--revision",1,"--json","-",payload={"summary":"每一层在共享表示上添加计算结果"})
    assert changed["content"]["personalNote"]=="我的原创理解"
    assert "覆盖" in cli("update",eid,"--revision",1,"--json","-",payload={"summary":"旧的修改"},ok=False)["error"]
    cli("update",eid,"--revision",2,"--json","-",payload={"typo":"silent no-op must fail"},ok=False)
    reviewed=cli("review",eid,"--revision",2,"--rating",2)
    assert reviewed["mastery"]=="understood"
    removed=cli("delete",eid,"--revision",3)
    assert cli("list")["total"]==0 and cli("list","--trash")["total"]==1
    restored=cli("restore",eid,"--revision",4)
    assert restored.get("deletedAt") is None
    assert cli("get",eid)["revision"]==5
    assert len(cli("history",eid))==5
    print("PASS CLI create/read/update/conflict/review/trash/restore/history across independent processes")

    archive=directory/"backup.json"; cli("export",archive)
    second=directory/"second.sqlite"; cli("import",archive,db=second)
    assert cli("get",eid,db=second)["content"]["personalNote"]=="我的原创理解"
    assert cli("get",eid,db=second)["reviewCount"]==1
    markdown=directory/"notes.md"
    markdown.write_text("# 学习笔记\n\n### 模型\n\n1. **张量（Tensor）**\n* **大白话**：多维表格。\n\n2. **权重（Weight）**\n* **大白话**：参与模型计算的数字。\n",encoding="utf-8")
    imported=cli("import",markdown)
    assert imported["created"]==2
    collection=cli("collections")[0]
    assert cli("list","--collection",collection["id"])["entries"][0]["title"]=="张量"
    assert cli("import",markdown)["skipped"]==2
    print("PASS JSON backup retains notes/schedule; Markdown import retains reading order and skips duplicates")

    process=subprocess.Popen([str(BIN),"--database",str(database),"mcp"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    sequence=0
    def request(method, params=None):
        global sequence
        sequence+=1
        message={"jsonrpc":"2.0","id":sequence,"method":method}
        if params is not None: message["params"]=params
        process.stdin.write(json.dumps(message,ensure_ascii=False)+"\n"); process.stdin.flush()
        selector=selectors.DefaultSelector(); selector.register(process.stdout,selectors.EVENT_READ)
        if not selector.select(10): raise AssertionError("MCP response timed out")
        selector.close()
        reply=json.loads(process.stdout.readline())
        assert reply["id"]==sequence,reply
        return reply
    init=request("initialize",{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"verification","version":"1"}})
    assert init["result"]["serverInfo"]["name"]=="zhijian"
    process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');process.stdin.flush()
    assert "result" in request("ping")
    tools=request("tools/list")["result"]["tools"]
    assert len(tools)>=10
    def call(name,args):
        reply=request("tools/call",{"name":name,"arguments":args})["result"]
        assert not reply.get("isError"),reply
        return json.loads(reply["content"][0]["text"])
    assert call("search_entries",{"query":"传送带"})["total"]==1
    agent=call("create_entry",{"entry":{"title":"Agent 新增","summary":"经由 MCP 写入"}})
    assert cli("get",agent["id"])["content"]["summary"]=="经由 MCP 写入"
    updated=call("update_entry",{"id":agent["id"],"expected_revision":1,"patch":{"summary":"MCP 更新后的解释"}})
    assert updated["revision"]==2
    stale=request("tools/call",{"name":"delete_entry","arguments":{"id":agent["id"],"expected_revision":1}})
    assert stale["result"]["isError"]
    deleted=call("delete_entry",{"id":agent["id"],"expected_revision":2})
    call("restore_entry",{"id":agent["id"],"expected_revision":3})
    call("review_entry",{"id":agent["id"],"expected_revision":4,"rating":1})
    assert call("get_history",{"id":agent["id"]})[0]["actor"]=="mcp"
    invalid=request("tools/call",{"name":"import_entries","arguments":{"entries":[{"title":"原子有效","summary":"解释"},{"title":"","summary":"错误"}]}})
    assert invalid["result"]["isError"] and cli("list","--query","原子有效")["total"]==0
    batch=call("import_entries",{"entries":[{"id":"forward-a","title":"正向关联甲","summary":"解释甲","relatedIDs":["forward-b"]},{"id":"forward-b","title":"正向关联乙","summary":"解释乙"}],"collectionTitle":"Agent 阅读路径"})
    assert batch["created"]==2
    process.stdin.close(); process.wait(timeout=5)
    assert process.returncode==0 and not process.stderr.read()
    print("PASS real MCP initialize/notifications/ping/catalog/CRUD/review/history/atomic import/forward relations")

print("All subprocess checks passed; user library was not touched.")
