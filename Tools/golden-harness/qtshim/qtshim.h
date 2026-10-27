// SPDX-License-Identifier: MPL-2.0
// Minimal stand-in for the Qt classes used by imageformatter.cpp / sysex.cpp. Behaviour mirrors
// Qt where the formatter depends on it (QVariant conversions, QMap::value defaults, toLatin1).
#ifndef QTSHIM_H
#define QTSHIM_H
#include "QtGlobal"
#include <cmath>
#include <cstdlib>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

class QChar {
public:
    QChar(char c = 0) : c(c) {}
    char c;
};

class QByteArray {
public:
    QByteArray() {}
    QByteArray(const std::string &s) : s(s) {}
    char at(int i) const { return s.at(i); }
    std::string s;
};

class QString {
public:
    QString() {}
    QString(const char *c) : s(c ? c : "") {}
    QString(const std::string &s) : s(s) {}
    QString(QChar c) : s(1, c.c) {}
    int length() const { return (int)s.size(); }
    bool isNull() const { return s.empty(); }
    bool endsWith(const QString &o) const { return s.size() >= o.s.size() && s.compare(s.size() - o.s.size(), o.s.size(), o.s) == 0; }
    QByteArray toLatin1() const { return QByteArray(s); } // inputs are ASCII
    template <typename T> QString arg(const T &value) const {
        std::ostringstream os;
        os << value;
        return replaceLowest(os.str());
    }
    QString arg(const QString &value) const { return replaceLowest(value.s); }
    QString arg(const char *value) const { return replaceLowest(value); }
    QString &operator+=(const QString &o) { s += o.s; return *this; }
    QString &operator+=(QChar c) { s += c.c; return *this; }
    QString &operator=(char c) { s = std::string(1, c); return *this; }
    bool operator==(const QString &o) const { return s == o.s; }
    bool operator!=(const QString &o) const { return s != o.s; }
    bool operator<(const QString &o) const { return s < o.s; }
    std::string s;
private:
    // QString::arg replaces the lowest-numbered %N marker.
    QString replaceLowest(const std::string &value) const {
        int lowest = 100; size_t pos = std::string::npos;
        for (size_t i = 0; i + 1 < s.size(); i++)
            if (s[i] == '%' && s[i + 1] >= '1' && s[i + 1] <= '9' && s[i + 1] - '0' < lowest) { lowest = s[i + 1] - '0'; pos = i; }
        if (pos == std::string::npos) return *this;
        std::string out;
        for (size_t i = 0; i < s.size(); i++) {
            if (s[i] == '%' && i + 1 < s.size() && s[i + 1] - '0' == lowest) { out += value; i++; } else out += s[i];
        }
        return QString(out);
    }
};
inline QString operator+(const QString &a, const QString &b) { return QString(a.s + b.s); }
inline QString operator+(const QString &a, QChar b) { return QString(a.s + b.c); }

class QVariant;
template <typename K, typename V> class QMap {
public:
    V value(const K &key, const V &fallback = V()) const { auto it = m.find(key); return it == m.end() ? fallback : it->second; }
    void insert(const K &key, const V &value) { m[key] = value; }
    V &operator[](const K &key) { return m[key]; }
    int size() const { return (int)m.size(); }
    std::map<K, V> m;
};

class QVariant {
public:
    enum Kind { Null, Int, Double, String, Map };
    QVariant() : kind(Null) {}
    QVariant(int v) : kind(Int), i(v) {}
    QVariant(double v) : kind(Double), d(v) {}
    QVariant(const QString &v) : kind(String), str(v) {}
    QVariant(const QMap<QString, QVariant> &v);
    bool isNull() const { return kind == Null; }
    int toInt() const {
        switch (kind) {
        case Int: return i;
        case Double: return (int)std::llround(d); // QVariant rounds doubles
        case String: { char *end; long v = std::strtol(str.s.c_str(), &end, 10); return (*end == 0 && !str.s.empty()) ? (int)v : 0; }
        default: return 0;
        }
    }
    double toDouble() const {
        switch (kind) {
        case Int: return i;
        case Double: return d;
        case String: { char *end; double v = std::strtod(str.s.c_str(), &end); return (*end == 0 && !str.s.empty()) ? v : 0; }
        default: return 0;
        }
    }
    QString toString() const {
        switch (kind) {
        case Int: return QString(std::to_string(i));
        case String: return str;
        default: return QString();
        }
    }
    QMap<QString, QVariant> toMap() const;
    Kind kind; int i = 0; double d = 0; QString str;
    std::shared_ptr<QMap<QString, QVariant>> map;
};
typedef QMap<QString, QVariant> QVariantMap;
inline QVariant::QVariant(const QVariantMap &v) : kind(Map), map(std::make_shared<QVariantMap>(v)) {}
inline QVariantMap QVariant::toMap() const { return map ? *map : QVariantMap(); }

class QStringList : public std::vector<QString> {
public:
    QStringList &operator<<(const QString &s) { push_back(s); return *this; }
};

// Logging and file output are no-ops: the harness only needs the bytes.
struct QDebugShim {
    template <typename T> QDebugShim &operator<<(const T &) { return *this; }
};
inline QDebugShim qDebug() { return QDebugShim(); }
inline void qDebug(const char *, ...) {}

struct QIODevice { enum { WriteOnly = 1, Append = 2, Text = 4, ReadWrite = 8 }; };
class QFile {
public:
    QFile(const QString &) {}
    bool open(int) { return false; }
    void close() {}
    bool remove() { return false; }
};
class QTextStream {
public:
    QTextStream(QFile *) {}
    template <typename T> QTextStream &operator<<(const T &) { return *this; }
};
struct QStandardPaths { enum { DownloadLocation }; static QString writableLocation(int) { return QString("/tmp"); } };
struct QDir { static QChar separator() { return QChar('/'); } };
#define APP_VERSION "golden-harness"
#endif
