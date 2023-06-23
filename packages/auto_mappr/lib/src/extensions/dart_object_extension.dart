//ignore_for_file: no-object-declaration

import 'package:analyzer/dart/constant/value.dart';
import 'package:auto_mappr/src/extensions/element_extension.dart';
import 'package:auto_mappr/src/extensions/executable_element_extension.dart';
import 'package:auto_mappr/src/models/auto_mappr_config.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';

extension DartObjectExtension on DartObject {
  /// If the top most object is a function, then return its code expression.
  ///
  /// Otherwise return code expression of literals or objects.
  Expression? toCodeExpression({
    required AutoMapprConfig config,
    bool passModelArgument = false,
  }) {
    if (isNull) {
      return null;
    }

    // If the top most object is function, call it.
    final asFunction = toFunctionValue();
    if (asFunction != null) {
      return refer(asFunction.referCallString).call([
        if (passModelArgument) refer('model'),
      ]);
    }

    final emitter = DartEmitter();
    final output = _ToCodeExpressionConverter(config: config).convert(this).accept(emitter);

    return CodeExpression(Code('$output'));
  }
}

class _ToCodeExpressionConverter {
  final AutoMapprConfig config;

  _ToCodeExpressionConverter({required this.config});

  Spec convert(DartObject dartObject) {
    return _toSpec(dartObject);
  }

  Spec _toSpec(DartObject dartObject) {
    final constant = ConstantReader(dartObject);

    if (constant.isLiteral) {
      return _reviveLiteral(dartObject);
    }

    /// Perhaps an object instantiation?
    return _reviveObject(dartObject);
  }

  Spec _reviveLiteral(DartObject dartObject) {
    final constant = ConstantReader(dartObject);

    // Special literals

    if (constant.isSymbol) {
      return Code('Symbol(${constant.symbolValue})');
    }

    if (constant.isType) {
      return Code('Symbol(${constant.symbolValue})');
    }

    if (constant.isString) {
      return literalString(constant.stringValue, raw: true);
    }

    // Collections

    if (constant.isList) {
      return literalList(constant.listValue.map(_toSpec));
    }

    if (constant.isSet) {
      return literalSet(constant.setValue.map(_toSpec));
    }

    if (constant.isMap) {
      return literalMap(
        constant.mapValue.map((key, value) => MapEntry(_toSpec(key!), _toSpec(value!))),
      );
    }

    // int, double, num, null
    return literal(constant.literalValue);
  }

  Spec _reviveObject(DartObject dartObject) {
    final revived = ConstantReader(dartObject).revive();

    final location = revived.source.toString().split('#');
    final libraryAlias = dartObject.type!.element!.getLibraryAlias(config: config);

    // Getters, Setters, Methods can't be declared as constants so this
    // literal must either be a top-level constant or a static constant and
    // can be directly accessed by `revived.accessor`.
    if (location.length <= 1) {
      return refer('$libraryAlias${revived.accessor}');
    }

    // If this is a class instantiation then `location[1]` will be populated
    // with the class name.
    //
    // location[1] - class
    // revived.accessor - named constructor
    final instantiation = location[1];
    final useNamedConstructor = revived.accessor.isNotEmpty;

    final revivedInstance = refer('$libraryAlias$instantiation');

    final positionalArguments =
        revived.positionalArguments.map<Expression>((argument) => _toSpec(argument) as Expression);
    final namedArguments =
        revived.namedArguments.map<String, Expression>((key, value) => MapEntry(key, _toSpec(value) as Expression));

    if (useNamedConstructor) {
      return revivedInstance.constInstanceNamed(revived.accessor, positionalArguments, namedArguments);
    }

    return revivedInstance.constInstance(positionalArguments, namedArguments);
  }
}
