# Portable awk; accepts ordinary block-style YAML and preserves unrelated text.
function spaces(n, s, i) { s=""; for(i=0;i<n;i++) s=s " "; return s }
function indent(s, t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
function scalar(s, q) {
    sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); sub(/[ \t]+$/, "", s)
    q=substr(s,1,1); if ((q=="\047" || q=="\042") && substr(s,length(s),1)==q) s=substr(s,2,length(s)-2)
    return s
}
function fail(message) { print "Setup: " message > "/dev/stderr"; failed=1; exit 2 }
function emit_managed( line) {
    if (emitted) return
    if (list_indent < 0) list_indent=2
    print spaces(list_indent) "# BEGIN git-cli-kit managed commands"
    while ((getline line < body)>0) print spaces(list_indent) substr(line,3)
    close(body)
    print spaces(list_indent) "# END git-cli-kit managed commands"
    emitted=1
}
function flush_item( i,k,c,cmd,context_line,remaining,n,a,collision) {
    if (item_count==0) return
    k=""; c=""; cmd=""; context_line=0
    for(i=1;i<=item_count;i++) {
        if(item[i] ~ /^[ ]*(-[ ]*)?key:/) k=scalar(item[i])
        if(item[i] ~ /^[ ]*context:/) { c=scalar(item[i]); context_line=i }
        if(item[i] ~ /^[ ]*command:/) cmd=scalar(item[i])
    }
    gsub(/<c-/,"<ctrl+",k)
    n=split(c,a,","); remaining=""; collision=0
    for(i=1;i<=n;i++) {
        gsub(/^[ \t]+|[ \t]+$/,"",a[i])
        if(a[i]=="files") collision=1
        else if(a[i]!="") remaining=remaining (remaining==""?"":", ") a[i]
    }
    if (collision && k ~ /^\[/ && k ~ /(^|[^A-Za-z])(e|<ctrl\+b>|<ctrl\+m>|<f7>)([^A-Za-z]|$)/)
        fail("A custom command uses a multi-key list that overlaps e/Ctrl+B/F7. Split that item into single-key block YAML and rerun.")
    collision=collision && (k=="e" || k=="<ctrl+b>" || k=="<f7>" || (k=="<ctrl+m>" && cmd ~ /mergetool/))
    if(!collision || remaining!="") {
        if(collision && context_line) item[context_line]=spaces(indent(item[context_line])) "context: '" remaining "'"
        for(i=1;i<=item_count;i++) print item[i]
    }
    for(i=1;i<=item_count;i++) delete item[i]
    item_count=0
}
BEGIN { inside=0; found=0; emitted=0; skipping=0; list_indent=-1; item_count=0; failed=0 }
{
    sub(/\r$/, "")
    if($0 ~ /^[ \t]*# BEGIN git-cli-kit managed commands[ \t]*$/) { skipping=1; next }
    if(skipping) { if($0 ~ /^[ \t]*# END git-cli-kit managed commands[ \t]*$/) skipping=0; next }
    if($0 ~ /^customCommands:/) {
        if(found) fail("Duplicate top-level customCommands keys; fix the YAML first.")
        if($0 !~ /^customCommands:[ \t]*(#.*)?$/ && $0 !~ /^customCommands:[ \t]*(\[\]|null|~)[ \t]*(#.*)?$/)
            fail("customCommands must use block-style YAML, not an inline flow list.")
        found=1; inside=1; print "customCommands:"; next
    }
    if(inside && $0 ~ /^[A-Za-z_][A-Za-z0-9_.-]*:/) {
        flush_item(); emit_managed(); inside=0
    }
    if(inside) {
        if($0 ~ /^[ ]*-[ ]/) {
            current_indent=indent($0)
            if(list_indent<0) { list_indent=current_indent; emit_managed() }
            if(current_indent==list_indent) { flush_item(); item[++item_count]=$0; next }
        }
        if(item_count>0) item[++item_count]=$0
        else print
        next
    }
    if(!found && $0 ~ /^[ \t]*\{/) fail("JSON/flow-style config is not supported; convert it to block YAML first.")
    print
}
END {
    if(failed) exit 2
    if(skipping) { print "Setup: unterminated managed YAML block" > "/dev/stderr"; exit 2 }
    flush_item()
    if(!found) print "customCommands:"
    emit_managed()
}
