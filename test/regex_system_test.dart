import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Système Regex Complet', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Regex Literals', () {
      test('reconnaissance des regex literals simples', () {
        expect(interpreter.eval('/hello/').toString(), equals('/hello/'));
        expect(interpreter.eval('/world/i').toString(), equals('/world/i'));
        expect(interpreter.eval('/test/gi').toString(), equals('/test/gi'));
      });

      test('patterns complexes', () {
        expect(interpreter.eval(r'/\d+/').toString(), equals(r'/\d+/'));
        expect(interpreter.eval(r'/[a-z]+/i').toString(), equals(r'/[a-z]+/i'));
        expect(
          interpreter.eval(r'/^start.*end$/gm').toString(),
          equals(r'/^start.*end$/gm'),
        );
      });

      test('échappement de caractères', () {
        expect(interpreter.eval(r'/a\/b/').toString(), equals(r'/a\/b/'));
        expect(
          interpreter.eval(r'/\d{3}-\d{2}-\d{4}/').toString(),
          equals(r'/\d{3}-\d{2}-\d{4}/'),
        );
      });
    });

    group('Constructeur RegExp', () {
      test('création basique', () {
        expect(
          interpreter.eval('new RegExp("hello")').toString(),
          equals('/hello/'),
        );
        expect(
          interpreter.eval('new RegExp("world", "i")').toString(),
          equals('/world/i'),
        );
        expect(
          interpreter.eval('new RegExp("test", "gi")').toString(),
          equals('/test/gi'),
        );
      });

      test('équivalence constructeur vs literal', () {
        expect(
          interpreter.eval('new RegExp("hello", "i").source').toString(),
          equals('hello'),
        );
        expect(
          interpreter.eval('new RegExp("test", "gi").flags').toString(),
          equals('gi'),
        );
      });
    });

    group('Propriétés RegExp', () {
      test('propriété source', () {
        expect(interpreter.eval('/hello/i.source').toString(), equals('hello'));
        expect(
          interpreter.eval('new RegExp("world", "g").source').toString(),
          equals('world'),
        );
      });

      test('propriété flags', () {
        expect(interpreter.eval('/hello/i.flags').toString(), equals('i'));
        expect(interpreter.eval('/test/gim.flags').toString(), equals('gim'));
        expect(
          interpreter.eval('new RegExp("hello", "gi").flags').toString(),
          equals('gi'),
        );
      });

      test('propriétés booléennes de flags', () {
        expect(interpreter.eval('/hello/i.ignoreCase').toBoolean(), isTrue);
        expect(interpreter.eval('/hello/g.global').toBoolean(), isTrue);
        expect(interpreter.eval('/hello/m.multiline').toBoolean(), isTrue);
        expect(interpreter.eval('/hello/.global').toBoolean(), isFalse);
        expect(interpreter.eval('/hello/.ignoreCase').toBoolean(), isFalse);
      });

      test('propriété lastIndex', () {
        expect(interpreter.eval('/hello/g.lastIndex').toNumber(), equals(0));
      });
    });

    group('Méthodes RegExp', () {
      test('méthode test()', () {
        expect(
          interpreter.eval('/hello/i.test("Hello World")').toBoolean(),
          isTrue,
        );
        expect(
          interpreter.eval('/hello/i.test("Hi there")').toBoolean(),
          isFalse,
        );
        expect(
          interpreter.eval(r'/\d+/.test("abc123def")').toBoolean(),
          isTrue,
        );
        expect(interpreter.eval(r'/\d+/.test("abcdef")').toBoolean(), isFalse);
      });

      test('méthode exec() - match simple', () {
        final result = interpreter.eval(r'/\d+/.exec("abc123def")');
        expect(result.toString(), equals('123'));

        final resultWithIndex = interpreter.eval(
          r'let m = /\d+/.exec("abc123def"); m.index',
        );
        expect(resultWithIndex.toNumber(), equals(3));
      });

      test('méthode exec() - groupes de capture', () {
        final result = interpreter.eval(r'/([a-z]+)(\d+)/.exec("hello123")');
        expect(result.toString(), equals('hello123,hello,123'));

        expect(
          interpreter.eval(r'/([a-z]+)(\d+)/.exec("hello123")[0]').toString(),
          equals('hello123'),
        );
        expect(
          interpreter.eval(r'/([a-z]+)(\d+)/.exec("hello123")[1]').toString(),
          equals('hello'),
        );
        expect(
          interpreter.eval(r'/([a-z]+)(\d+)/.exec("hello123")[2]').toString(),
          equals('123'),
        );
      });

      test('méthode exec() - pas de match', () {
        expect(
          interpreter.eval('/xyz/.exec("hello world")').toString(),
          equals('null'),
        );
      });
    });

    group('String.match()', () {
      test('match simple', () {
        expect(
          interpreter.eval('"Hello World".match(/o/)').toString(),
          equals('o'),
        );
        expect(
          interpreter.eval('"Hello World".match(/xyz/)').toString(),
          equals('null'),
        );
      });

      test('match global', () {
        expect(
          interpreter.eval('"Hello World".match(/o/g)').toString(),
          equals('o,o'),
        );
        expect(
          interpreter.eval('"Hello World".match(/[a-z]/g)').toString(),
          equals('e,l,l,o,o,r,l,d'),
        );
      });

      test('match avec groupes', () {
        final result = interpreter.eval(
          r'"email@example.com".match(/(\w+)@(\w+)\.(\w+)/)',
        );
        expect(
          result.toString(),
          equals('email@example.com,email,example,com'),
        );
      });
    });

    group('String.search()', () {
      test('search basique', () {
        expect(
          interpreter.eval('"Hello World".search(/o/)').toNumber(),
          equals(4),
        );
        expect(
          interpreter.eval('"Hello World".search(/World/)').toNumber(),
          equals(6),
        );
        expect(
          interpreter.eval('"Hello World".search(/xyz/)').toNumber(),
          equals(-1),
        );
      });

      test('search avec pattern complexe', () {
        expect(
          interpreter.eval(r'"Price: $123.45".search(/\d+\.\d+/)').toNumber(),
          equals(8),
        );
      });
    });

    group('String.replace()', () {
      test('replace simple', () {
        expect(
          interpreter.eval('"Hello World".replace(/o/, "X")').toString(),
          equals('HellX World'),
        );
        expect(
          interpreter.eval('"Hello World".replace(/xyz/, "X")').toString(),
          equals('Hello World'),
        );
      });

      test('replace global', () {
        expect(
          interpreter.eval('"Hello World".replace(/o/g, "X")').toString(),
          equals('HellX WXrld'),
        );
        expect(
          interpreter.eval('"Hello World".replace(/[a-z]/g, "X")').toString(),
          equals('HXXXX WXXXX'),
        );
      });

      test('replace avec pattern complexe', () {
        expect(
          interpreter
              .eval(
                r'"Phone: 123-456-7890".replace(/\d{3}-\d{3}-\d{4}/, "XXX-XXX-XXXX")',
              )
              .toString(),
          equals('Phone: XXX-XXX-XXXX'),
        );
      });
    });

    group('String.split()', () {
      test('split avec regex simple', () {
        expect(
          interpreter.eval('"a,b,c".split(/,/)').toString(),
          equals('a,b,c'),
        );
      });

      test('split avec pattern complexe', () {
        expect(
          interpreter.eval('"a,b;c:d".split(/[,;:]/)').toString(),
          equals('a,b,c,d'),
        );
        expect(
          interpreter.eval(r'"hello123world456".split(/\d+/)').toString(),
          equals('hello,world,'),
        );
        expect(
          interpreter.eval(r'"a  b   c".split(/\s+/)').toString(),
          equals('a,b,c'),
        );
      });
    });

    group('Cas d\'usage réalistes', () {
      test('validation email', () {
        final emailRegex = r'/^[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}$/';
        expect(
          interpreter.eval('$emailRegex.test("user@example.com")').toBoolean(),
          isTrue,
        );
        expect(
          interpreter.eval('$emailRegex.test("invalid-email")').toBoolean(),
          isFalse,
        );
      });

      test('extraction de nombres', () {
        expect(
          interpreter.eval(r'"Prix: 123.45€".match(/\d+\.\d+/)[0]').toString(),
          equals('123.45'),
        );
      });

      test('nettoyage de texte', () {
        expect(
          interpreter
              .eval(r'"  hello   world  ".replace(/\s+/g, " ").trim()')
              .toString(),
          equals('hello world'),
        );
      });

      test('validation numéro de téléphone', () {
        final phoneRegex = r'/^\d{3}-\d{3}-\d{4}$/';
        expect(
          interpreter.eval('$phoneRegex.test("123-456-7890")').toBoolean(),
          isTrue,
        );
        expect(
          interpreter.eval('$phoneRegex.test("123-45-6789")').toBoolean(),
          isFalse,
        );
      });
    });

    group('Patterns avancés', () {
      test('groupes de capture nommés simulés', () {
        final result = interpreter.eval(r'/^(\w+)\s+(\w+)$/.exec("John Doe")');
        expect(result.toString(), equals('John Doe,John,Doe'));
      });

      test('classes de caractères', () {
        expect(interpreter.eval('/[A-Z]/.test("Hello")').toBoolean(), isTrue);
        expect(interpreter.eval('/[a-z]/.test("HELLO")').toBoolean(), isFalse);
        expect(
          interpreter.eval('/[0-9]/.test("Hello123")').toBoolean(),
          isTrue,
        );
      });

      test('quantificateurs', () {
        expect(interpreter.eval(r'/\d{3}/.test("123")').toBoolean(), isTrue);
        expect(interpreter.eval(r'/\d{3}/.test("12")').toBoolean(), isFalse);
        expect(interpreter.eval(r'/\d{2,4}/.test("123")').toBoolean(), isTrue);
      });

      test('ancres', () {
        expect(
          interpreter.eval('/^hello/.test("hello world")').toBoolean(),
          isTrue,
        );
        expect(
          interpreter.eval('/^hello/.test("say hello")').toBoolean(),
          isFalse,
        );
        expect(
          interpreter.eval(r'/world$/.test("hello world")').toBoolean(),
          isTrue,
        );
        expect(
          interpreter.eval(r'/world$/.test("world peace")').toBoolean(),
          isFalse,
        );
      });
    });

    group('Flags spéciaux', () {
      test('flag multiline (m)', () {
        expect(
          interpreter.eval(r'/^line/m.test("first\nline")').toBoolean(),
          isTrue,
        );
      });

      test('flag case insensitive (i)', () {
        expect(interpreter.eval('/HELLO/i.test("hello")').toBoolean(), isTrue);
        expect(interpreter.eval('/hello/.test("HELLO")').toBoolean(), isFalse);
      });

      test('flag global (g) avec lastIndex', () {
        // Le flag global affecte le comportement de exec() et test()
        expect(interpreter.eval('/o/g.global').toBoolean(), isTrue);
        expect(interpreter.eval('/o/.global').toBoolean(), isFalse);
      });
    });

    group('Compatibilité constructeur vs literal', () {
      test('même comportement test()', () {
        expect(
          interpreter
              .eval(
                '{ let lit = /hello/i; let con = new RegExp("hello", "i"); lit.test("HELLO") === con.test("HELLO") }',
              )
              .toBoolean(),
          isTrue,
        );
      });

      test('même comportement exec()', () {
        expect(
          interpreter
              .eval(
                r'{ let lit = /\d+/; let con = new RegExp("\\d+"); lit.exec("abc123")[0] === con.exec("abc123")[0] }',
              )
              .toBoolean(),
          isTrue,
        );
      });

      test('mêmes propriétés', () {
        expect(
          interpreter
              .eval(
                '{ let lit = /hello/gi; let con = new RegExp("hello", "gi"); lit.source === con.source && lit.flags === con.flags }',
              )
              .toBoolean(),
          isTrue,
        );
      });
    });
  });
}
