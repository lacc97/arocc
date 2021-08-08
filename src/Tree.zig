const std = @import("std");
const Type = @import("Type.zig");
const Tokenizer = @import("Tokenizer.zig");
const Compilation = @import("Compilation.zig");
const Source = @import("Source.zig");

const Tree = @This();

pub const Token = struct {
    id: Id,
    /// This location contains the actual token slice which might be generated.
    /// If it is generated then the next location will be the location of the concatenation.
    /// Any subsequent locations mark where the token was expanded from. 
    loc: Source.Location,

    pub const List = std.MultiArrayList(Token);
    pub const Id = Tokenizer.Token.Id;
};

pub const TokenIndex = u32;
pub const NodeIndex = enum(u32) { none, _ };
pub const ValueMap = std.AutoHashMap(NodeIndex, u64);

comp: *Compilation,
arena: std.heap.ArenaAllocator,
generated: []const u8,
tokens: Token.List.Slice,
nodes: Node.List.Slice,
data: []const NodeIndex,
root_decls: []const NodeIndex,
strings: []const u8,
value_map: ValueMap,

pub fn deinit(tree: *Tree) void {
    tree.comp.gpa.free(tree.root_decls);
    tree.comp.gpa.free(tree.data);
    tree.comp.gpa.free(tree.strings);
    tree.nodes.deinit(tree.comp.gpa);
    tree.arena.deinit();
    tree.value_map.deinit();
}

pub const Node = struct {
    tag: Tag,
    ty: Type = .{ .specifier = .void },
    data: Data,

    pub const Data = union {
        decl: struct {
            name: TokenIndex,
            node: NodeIndex = .none,
        },
        decl_ref: TokenIndex,
        range: struct {
            start: u32,
            end: u32,
        },
        if3: struct {
            cond: NodeIndex,
            body: u32,
        },
        str: struct {
            index: u32,
            len: u32,
        },
        un: NodeIndex,
        bin: struct {
            lhs: NodeIndex,
            rhs: NodeIndex,
        },
        int: u64,
        float: f32,
        double: f64,

        pub fn forDecl(data: Data, tree: Tree) struct {
            decls: []const NodeIndex,
            cond: NodeIndex,
            incr: NodeIndex,
            body: NodeIndex,
        } {
            const items = tree.data[data.range.start..data.range.end];
            const decls = items[0 .. items.len - 3];

            return .{
                .decls = decls,
                .cond = items[items.len - 3],
                .incr = items[items.len - 2],
                .body = items[items.len - 1],
            };
        }

        pub fn forStmt(data: Data, tree: Tree) struct {
            init: NodeIndex,
            cond: NodeIndex,
            incr: NodeIndex,
            body: NodeIndex,
        } {
            const items = tree.data[data.if3.body..];

            return .{
                .init = items[0],
                .cond = items[1],
                .incr = items[2],
                .body = data.if3.cond,
            };
        }
    };

    pub const List = std.MultiArrayList(Node);
};

pub const Tag = enum(u8) {
    /// Only appears at index 0 and reaching it is always a result of a bug.
    invalid,

    // ====== Decl ======

    // _Static_assert
    static_assert,

    // function prototype
    fn_proto,
    static_fn_proto,
    inline_fn_proto,
    inline_static_fn_proto,
    noreturn_fn_proto,
    noreturn_static_fn_proto,
    noreturn_inline_fn_proto,
    noreturn_inline_static_fn_proto,

    // function definition
    fn_def,
    static_fn_def,
    inline_fn_def,
    inline_static_fn_def,
    noreturn_fn_def,
    noreturn_static_fn_def,
    noreturn_inline_fn_def,
    noreturn_inline_static_fn_def,

    // a parameter
    param_decl,
    register_param_decl,

    // variable declaration
    @"var",
    extern_var,
    static_var,
    register_var,
    threadlocal_var,
    threadlocal_extern_var,
    threadlocal_static_var,

    // typedef declaration
    typedef,

    // container definitions
    struct_def,
    union_def,
    enum_def,

    // ====== Stmt ======

    labeled_stmt,
    /// { first; second; } first and second may be null
    compound_stmt_two,
    /// { data }
    compound_stmt,
    /// if (first) data[second] else data[second+1];
    if_then_else_stmt,
    /// if (first); else second;
    if_else_stmt,
    /// if (first) second; second may be null
    if_then_stmt,
    /// switch (first) second
    switch_stmt,
    /// case first: second
    case_stmt,
    /// default: first
    default_stmt,
    /// while (first) second
    while_stmt,
    /// do second while(first);
    do_while_stmt,
    /// for (data[..]; data[len-3]; data[len-2]) data[len-1]
    for_decl_stmt,
    /// for (;;;) first
    forever_stmt,
    /// for (data[first]; data[first+1]; data[first+2]) second
    for_stmt,
    /// goto first;
    goto_stmt,
    // continue; first and second unused
    continue_stmt,
    // break; first and second unused
    break_stmt,
    /// return first; first may be null
    return_stmt,

    // ====== Expr ======

    /// lhs , rhs
    comma_expr,
    /// lhs ?: rhs
    binary_cond_expr,
    /// lhs ? data[0] : data[1]
    cond_expr,
    /// lhs = rhs
    assign_expr,
    /// lhs *= rhs
    mul_assign_expr,
    /// lhs /= rhs
    div_assign_expr,
    /// lhs %= rhs
    mod_assign_expr,
    /// lhs += rhs
    add_assign_expr,
    /// lhs -= rhs
    sub_assign_expr,
    /// lhs <<= rhs
    shl_assign_expr,
    /// lhs >>= rhs
    shr_assign_expr,
    /// lhs &= rhs
    bit_and_assign_expr,
    /// lhs ^= rhs
    bit_xor_assign_expr,
    /// lhs |= rhs
    bit_or_assign_expr,
    /// lhs || rhs
    bool_or_expr,
    /// lhs && rhs
    bool_and_expr,
    /// lhs | rhs
    bit_or_expr,
    /// lhs ^ rhs
    bit_xor_expr,
    /// lhs & rhs
    bit_and_expr,
    /// lhs == rhs
    equal_expr,
    /// lhs != rhs
    not_equal_expr,
    /// lhs < rhs
    less_than_expr,
    /// lhs <= rhs
    less_than_equal_expr,
    /// lhs > rhs
    greater_than_expr,
    /// lhs >= rhs
    greater_than_equal_expr,
    /// lhs << rhs
    shl_expr,
    /// lhs >> rhs
    shr_expr,
    /// lhs + rhs
    add_expr,
    /// lhs - rhs
    sub_expr,
    /// lhs * rhs
    mul_expr,
    /// lhs / rhs
    div_expr,
    /// lhs % rhs
    mod_expr,
    /// Explicit (type)un
    cast_expr,
    /// &un
    addr_of_expr,
    /// *un
    deref_expr,
    /// +un
    plus_expr,
    /// -un
    negate_expr,
    /// ~un
    bit_not_expr,
    /// !un
    bool_not_expr,
    /// ++un
    pre_inc_expr,
    /// --un
    pre_dec_expr,
    /// lhs[rhs]  lhs is pointer/array type, rhs is integer type
    array_access_expr,
    /// first(second) second may be 0
    call_expr_one,
    /// data[0](data[1..])
    call_expr,
    /// lhs.rhs rhs is a TokenIndex of the identifier
    member_access_expr,
    /// lhs->rhs rhs is a TokenIndex of the identifier
    member_access_ptr_expr,
    /// un++
    post_inc_expr,
    /// un--
    post_dec_expr,
    /// (un)
    paren_expr,
    /// decl
    decl_ref_expr,
    /// decl_ref
    enumeration_ref,
    /// integer literal, always unsigned
    int_literal,
    /// f32 literal
    float_literal,
    /// f64 literal
    double_literal,
    /// tree.str[index..][0..len]
    string_literal_expr,
    /// TODO
    compound_literal_expr,

    // ====== Implicit casts ======

    /// convert T[] to T *
    array_to_pointer,
    /// same as deref
    lval_to_rval,
};

pub fn isLval(nodes: Node.List.Slice, node: NodeIndex) bool {
    switch (nodes.items(.tag)[@enumToInt(node)]) {
        .compound_literal_expr => return true,
        .string_literal_expr => return true,
        .member_access_ptr_expr => return true,
        .array_access_expr => return true,
        .decl_ref_expr => return true,
        .deref_expr => {
            const data = nodes.items(.data)[@enumToInt(node)];
            return !nodes.items(.ty)[@enumToInt(data.un)].isFunc();
        },
        .member_access_expr => {
            const data = nodes.items(.data)[@enumToInt(node)];
            return isLval(nodes, data.bin.lhs);
        },
        .paren_expr => {
            const data = nodes.items(.data)[@enumToInt(node)];
            return isLval(nodes, data.un);
        },
        else => return false,
    }
}

pub fn dumpStr(bytes: []const u8, tag: Tag, writer: anytype) !void {
    switch (tag) {
        .string_literal_expr => try writer.print("\"{}\"", .{std.zig.fmtEscapes(bytes)}),
        else => unreachable,
    }
}

pub fn tokSlice(tree: Tree, tok_i: TokenIndex) []const u8 {
    if (tree.tokens.items(.id)[tok_i].lexeme()) |some| return some;
    const loc = tree.tokens.items(.loc)[tok_i];
    var tmp_tokenizer = Tokenizer{
        .buf = if (loc.id == .generated)
            tree.generated
        else
            tree.comp.getSource(loc.id).buf,
        .index = loc.byte_offset,
        .source = .generated,
    };
    const tok = tmp_tokenizer.next();
    return tmp_tokenizer.buf[tok.start..tok.end];
}

pub fn dump(tree: Tree, writer: anytype) @TypeOf(writer).Error!void {
    for (tree.root_decls) |i| {
        try tree.dumpNode(i, 0, writer);
        try writer.writeByte('\n');
    }
}

fn dumpNode(tree: Tree, node: NodeIndex, level: u32, w: anytype) @TypeOf(w).Error!void {
    const delta = 2;
    const half = delta / 2;
    const TYPE = "\x1b[35;1m";
    const TAG = "\x1b[36;1m";
    const NAME = "\x1b[91;1m";
    const LITERAL = "\x1b[32;1m";
    const ATTRIBUTE = "\x1b[93;1m";
    const RESET = "\x1b[0m";
    std.debug.assert(node != .none);

    const tag = tree.nodes.items(.tag)[@enumToInt(node)];
    const data = tree.nodes.items(.data)[@enumToInt(node)];
    const ty = tree.nodes.items(.ty)[@enumToInt(node)];
    try w.writeByteNTimes(' ', level);
    try w.print(TAG ++ "{s}: " ++ TYPE ++ "'", .{@tagName(tag)});
    try ty.dump(tree, w);
    try w.writeAll("'");
    if (isLval(tree.nodes, node)) {
        try w.writeAll(ATTRIBUTE ++ " lvalue");
    }
    if (tree.value_map.get(node)) |val| {
        if (ty.isUnsignedInt(tree.comp))
            try w.print(LITERAL ++ " (value: {d})" ++ RESET, .{val})
        else
            try w.print(LITERAL ++ " (value: {d})" ++ RESET, .{@bitCast(i64, val)});
    }
    try w.writeAll("\n" ++ RESET);
    switch (tag) {
        .invalid => unreachable,
        .static_assert => {
            try w.writeByteNTimes(' ', level + 1);
            try w.writeAll("condition:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);
            try w.writeByteNTimes(' ', level + 1);
            try w.writeAll("diagnostic:\n");
            try tree.dumpNode(data.bin.rhs, level + delta, w);
        },
        .fn_proto,
        .static_fn_proto,
        .inline_fn_proto,
        .inline_static_fn_proto,
        .noreturn_fn_proto,
        .noreturn_static_fn_proto,
        .noreturn_inline_fn_proto,
        .noreturn_inline_static_fn_proto,
        => {
            try w.writeByteNTimes(' ', level + half);
            try w.print("name: " ++ NAME ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl.name)});
        },
        .fn_def,
        .static_fn_def,
        .inline_fn_def,
        .inline_static_fn_def,
        .noreturn_fn_def,
        .noreturn_static_fn_def,
        .noreturn_inline_fn_def,
        .noreturn_inline_static_fn_def,
        => {
            try w.writeByteNTimes(' ', level + half);
            try w.print("name: " ++ NAME ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl.name)});
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("body:\n");
            try tree.dumpNode(data.decl.node, level + delta, w);
        },
        .typedef,
        .@"var",
        .extern_var,
        .static_var,
        .register_var,
        .threadlocal_var,
        .threadlocal_extern_var,
        .threadlocal_static_var,
        => {
            try w.writeByteNTimes(' ', level + half);
            try w.print("name: " ++ NAME ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl.name)});
            if (data.decl.node != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("init:\n");
                try tree.dumpNode(data.decl.node, level + delta, w);
            }
        },
        .enum_def => {
            for (ty.data.@"enum".fields) |field| {
                try w.writeByteNTimes(' ', level + half);
                try w.print(NAME ++ "{s}:\n" ++ RESET, .{tree.tokSlice(field.name)});
                if (field.node != .none) try tree.dumpNode(field.node, level + delta, w);
            }
        },
        .compound_stmt => {
            for (tree.data[data.range.start..data.range.end]) |stmt, i| {
                if (i != 0) try w.writeByte('\n');
                try tree.dumpNode(stmt, level + delta, w);
            }
        },
        .compound_stmt_two => {
            if (data.bin.lhs != .none) try tree.dumpNode(data.bin.lhs, level + delta, w);
            if (data.bin.rhs != .none) try tree.dumpNode(data.bin.rhs, level + delta, w);
        },
        .labeled_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.print("label: " ++ LITERAL ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl.name)});
            if (data.decl.node != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("stmt:\n");
                try tree.dumpNode(data.decl.node, level + delta, w);
            }
        },
        .case_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("value:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);
            if (data.bin.rhs != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("stmt:\n");
                try tree.dumpNode(data.bin.rhs, level + delta, w);
            }
        },
        .default_stmt => {
            if (data.un != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("stmt:\n");
                try tree.dumpNode(data.un, level + delta, w);
            }
        },
        .cond_expr, .if_then_else_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("cond:\n");
            try tree.dumpNode(data.if3.cond, level + delta, w);

            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("then:\n");
            try tree.dumpNode(tree.data[data.if3.body], level + delta, w);

            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("else:\n");
            try tree.dumpNode(tree.data[data.if3.body + 1], level + delta, w);
        },
        .if_else_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("cond:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);

            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("else:\n");
            try tree.dumpNode(data.bin.rhs, level + delta, w);
        },
        .if_then_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("cond:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);

            if (data.bin.rhs != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("then:\n");
                try tree.dumpNode(data.bin.rhs, level + delta, w);
            }
        },
        .switch_stmt, .while_stmt, .do_while_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("cond:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);

            if (data.bin.rhs != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("body:\n");
                try tree.dumpNode(data.bin.rhs, level + delta, w);
            }
        },
        .for_decl_stmt => {
            const for_decl = data.forDecl(tree);

            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("decl:\n");
            for (for_decl.decls) |decl| {
                try tree.dumpNode(decl, level + delta, w);
                try w.writeByte('\n');
            }
            if (for_decl.cond != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("cond:\n");
                try tree.dumpNode(for_decl.cond, level + delta, w);
            }
            if (for_decl.incr != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("incr:\n");
                try tree.dumpNode(for_decl.incr, level + delta, w);
            }
            if (for_decl.body != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("body:\n");
                try tree.dumpNode(for_decl.body, level + delta, w);
            }
        },
        .forever_stmt => {
            if (data.un != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("body:\n");
                try tree.dumpNode(data.un, level + delta, w);
            }
        },
        .for_stmt => {
            const for_stmt = data.forStmt(tree);

            if (for_stmt.init != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("init:\n");
                try tree.dumpNode(for_stmt.init, level + delta, w);
            }
            if (for_stmt.cond != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("cond:\n");
                try tree.dumpNode(for_stmt.cond, level + delta, w);
            }
            if (for_stmt.incr != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("incr:\n");
                try tree.dumpNode(for_stmt.incr, level + delta, w);
            }
            if (for_stmt.body != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("body:\n");
                try tree.dumpNode(for_stmt.body, level + delta, w);
            }
        },
        .goto_stmt => {
            try w.writeByteNTimes(' ', level + half);
            try w.print("label: " ++ LITERAL ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl_ref)});
        },
        .continue_stmt, .break_stmt => {},
        .return_stmt => {
            if (data.un != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("expr:\n");
                try tree.dumpNode(data.un, level + delta, w);
            }
        },
        .string_literal_expr => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("data: " ++ LITERAL);
            try dumpStr(tree.strings[data.str.index..][0..data.str.len], tag, w);
            try w.writeAll("\n" ++ RESET);
        },
        .call_expr => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("lhs:\n");
            try tree.dumpNode(tree.data[data.range.start], level + delta, w);

            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("args:\n");
            for (tree.data[data.range.start + 1 .. data.range.end]) |arg| try tree.dumpNode(arg, level + delta, w);
        },
        .call_expr_one => {
            try w.writeByteNTimes(' ', level + half);
            try w.writeAll("lhs:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);
            if (data.bin.rhs != .none) {
                try w.writeByteNTimes(' ', level + half);
                try w.writeAll("arg:\n");
                try tree.dumpNode(data.bin.rhs, level + delta, w);
            }
        },
        .comma_expr,
        .binary_cond_expr,
        .assign_expr,
        .mul_assign_expr,
        .div_assign_expr,
        .mod_assign_expr,
        .add_assign_expr,
        .sub_assign_expr,
        .shl_assign_expr,
        .shr_assign_expr,
        .bit_and_assign_expr,
        .bit_xor_assign_expr,
        .bit_or_assign_expr,
        .bool_or_expr,
        .bool_and_expr,
        .bit_or_expr,
        .bit_xor_expr,
        .bit_and_expr,
        .equal_expr,
        .not_equal_expr,
        .less_than_expr,
        .less_than_equal_expr,
        .greater_than_expr,
        .greater_than_equal_expr,
        .shl_expr,
        .shr_expr,
        .add_expr,
        .sub_expr,
        .mul_expr,
        .div_expr,
        .mod_expr,
        => {
            try w.writeByteNTimes(' ', level + 1);
            try w.writeAll("lhs:\n");
            try tree.dumpNode(data.bin.lhs, level + delta, w);
            try w.writeByteNTimes(' ', level + 1);
            try w.writeAll("rhs:\n");
            try tree.dumpNode(data.bin.rhs, level + delta, w);
        },
        .cast_expr,
        .addr_of_expr,
        .deref_expr,
        .plus_expr,
        .negate_expr,
        .bit_not_expr,
        .bool_not_expr,
        .pre_inc_expr,
        .pre_dec_expr,
        .post_inc_expr,
        .post_dec_expr,
        .paren_expr,
        .array_to_pointer,
        .lval_to_rval,
        => {
            try w.writeByteNTimes(' ', level + 1);
            try w.writeAll("operand:\n");
            try tree.dumpNode(data.un, level + delta, w);
        },
        .decl_ref_expr => {
            try w.writeByteNTimes(' ', level + 1);
            try w.print("name: " ++ NAME ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl.name)});
        },
        .enumeration_ref => {
            try w.writeByteNTimes(' ', level + 1);
            try w.print("name: " ++ NAME ++ "{s}\n" ++ RESET, .{tree.tokSlice(data.decl_ref)});
        },
        .int_literal => {
            try w.writeByteNTimes(' ', level + 1);
            try w.print("value: " ++ LITERAL ++ "{d}\n" ++ RESET, .{data.int});
        },
        .float_literal => {
            try w.writeByteNTimes(' ', level + 1);
            try w.print("value: " ++ LITERAL ++ "{d}\n" ++ RESET, .{data.float});
        },
        .double_literal => {
            try w.writeByteNTimes(' ', level + 1);
            try w.print("value: " ++ LITERAL ++ "{d}\n" ++ RESET, .{data.double});
        },
        else => {},
    }
}
