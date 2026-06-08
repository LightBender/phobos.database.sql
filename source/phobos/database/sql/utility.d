module phobos.database.sql.utility;

import odbc;
import std.array : empty;

class ODBCException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Throws an `ODBCException` built from `res` when the operation failed.
void enforceOk(T)(Result!T res, string context,
                  string file = __FILE__, size_t line = __LINE__) {
    if (res.isErr)
        throw new ODBCException(buildMessage(context, res.message), file, line);
}

/// Returns the value of a successful result, or throws an `ODBCException`
/// describing the failure.
T unwrap(T)(Result!T res, string context,
            string file = __FILE__, size_t line = __LINE__) {
    if (res.isErr)
        throw new ODBCException(buildMessage(context, res.message), file, line);
    return res.value;
}

private string buildMessage(string context, string detail) {
    return detail.empty ? context : context ~ ": " ~ detail;
}
