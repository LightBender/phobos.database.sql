module phobos.database.sql.utility;

import etc.c.odbc.odbc64;
import std.exception;
import std.format;
import std.string;

class ODBCException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

void checkError(SQLSMALLINT handleType, SQLHANDLE handle,
                SQLRETURN retcode, string funcName = __FUNCTION__) {
    if (retcode == SQL_SUCCESS || retcode == SQL_SUCCESS_WITH_INFO) {
        return;
    }

    enum MAX_MSG = 256;
    SQLCHAR[6] sqlState;
    SQLCHAR[MAX_MSG] messageText;
    SQLSMALLINT textLength;
    SQLSMALLINT recNum = 1;

    SQLRETURN diagRet = SQLGetDiagRec(handleType, handle, recNum,
                                      sqlState.ptr, null, messageText.ptr,
                                      cast(SQLSMALLINT)MAX_MSG, &textLength);
    string stateStr = cast(string)(sqlState[0 .. 5]);
    string msgStr = cast(string)(messageText[0 .. (textLength < MAX_MSG ? textLength : MAX_MSG)]);

    throw new ODBCException(format!"ODBC %s error (diag: %s): %s"(funcName, stateStr, msgStr));
}
