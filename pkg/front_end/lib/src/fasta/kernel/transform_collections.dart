// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.transform_collections;

import 'package:kernel/ast.dart'
    show
        Arguments,
        Block,
        BlockExpression,
        DartType,
        DynamicType,
        Expression,
        ExpressionStatement,
        ForInStatement,
        IfStatement,
        InterfaceType,
        InvalidExpression,
        ListLiteral,
        MethodInvocation,
        Name,
        Not,
        NullLiteral,
        Procedure,
        SetLiteral,
        Statement,
        StaticInvocation,
        TreeNode,
        VariableDeclaration,
        VariableGet;

import 'package:kernel/core_types.dart' show CoreTypes;

import 'package:kernel/visitor.dart' show Transformer;

import 'collections.dart' show SpreadElement;

import '../source/source_loader.dart' show SourceLoader;

import 'redirecting_factory_body.dart' show RedirectingFactoryBody;

class CollectionTransformer extends Transformer {
  final CoreTypes coreTypes;
  final Procedure listAdd;
  final Procedure setFactory;
  final Procedure setAdd;
  final Procedure objectEquals;

  static Procedure _findSetFactory(CoreTypes coreTypes) {
    Procedure factory = coreTypes.index.getMember('dart:core', 'Set', '');
    RedirectingFactoryBody body = factory?.function?.body;
    return body?.target;
  }

  CollectionTransformer(SourceLoader loader)
      : coreTypes = loader.coreTypes,
        listAdd = loader.coreTypes.index.getMember('dart:core', 'List', 'add'),
        setFactory = _findSetFactory(loader.coreTypes),
        setAdd = loader.coreTypes.index.getMember('dart:core', 'Set', 'add'),
        objectEquals =
            loader.coreTypes.index.getMember('dart:core', 'Object', '==');

  TreeNode _translateListOrSet(
      Expression node, DartType elementType, List<Expression> elements,
      {bool isSet: false, bool isConst: false}) {
    // Translate elements in place up to the first spread if any.
    int i = 0;
    for (; i < elements.length; ++i) {
      if (elements[i] is SpreadElement) break;
      elements[i] = elements[i].accept(this)..parent = node;
    }

    // If there was no spread, we are done.
    if (i == elements.length) return node;

    if (isConst) {
      // We don't desugar const lists here.  Remove spread for now so that they
      // don't leak out.
      for (; i < elements.length; ++i) {
        Expression element = elements[i];
        if (element is SpreadElement) {
          elements[i] = InvalidExpression('unimplemented spread element')
            ..fileOffset = element.fileOffset
            ..parent = node;
        } else {
          elements[i] = element.accept(this)..parent = node;
        }
      }
      return node;
    }

    // Build a block expression and create an empty list or set.
    VariableDeclaration result;
    if (isSet) {
      // TODO(kmillikin): When all the back ends handle set literals we can use
      // one here.
      result = new VariableDeclaration.forValue(
          new StaticInvocation(
              setFactory, new Arguments([], types: [elementType])),
          type: new InterfaceType(coreTypes.setClass, [elementType]),
          isFinal: true);
    } else {
      result = new VariableDeclaration.forValue(
          new ListLiteral([], typeArgument: elementType),
          type: new InterfaceType(coreTypes.listClass, [elementType]),
          isFinal: true);
    }
    List<Statement> body = [result];
    // Add the elements up to the first spread.
    for (int j = 0; j < i; ++j) {
      body.add(new ExpressionStatement(new MethodInvocation(
          new VariableGet(result),
          new Name('add'),
          new Arguments([elements[j]]),
          isSet ? setAdd : listAdd)));
    }
    // Translate the elements starting with the first spread.
    for (; i < elements.length; ++i) {
      Expression element = elements[i];
      if (element is SpreadElement) {
        Expression value = element.expression.accept(this);
        // Null-aware spreads require testing the subexpression's value.
        VariableDeclaration temp;
        if (element.isNullAware) {
          temp = new VariableDeclaration.forValue(value,
              type: const DynamicType(), isFinal: true);
          body.add(temp);
          value = new VariableGet(temp);
        }

        VariableDeclaration elt =
            new VariableDeclaration(null, type: elementType, isFinal: true);
        Statement statement = new ForInStatement(
            elt,
            value,
            new ExpressionStatement(new MethodInvocation(
                new VariableGet(result),
                new Name('add'),
                new Arguments([new VariableGet(elt)]),
                isSet ? setAdd : listAdd)));

        if (element.isNullAware) {
          statement = new IfStatement(
              new Not(new MethodInvocation(
                  new VariableGet(temp),
                  new Name('=='),
                  new Arguments([new NullLiteral()]),
                  objectEquals)),
              statement,
              null);
        }
        body.add(statement);
      } else {
        body.add(new ExpressionStatement(new MethodInvocation(
            new VariableGet(result),
            new Name('add'),
            new Arguments([element.accept(this)]),
            isSet ? setAdd : listAdd)));
      }
    }

    return new BlockExpression(new Block(body), new VariableGet(result));
  }

  @override
  TreeNode visitListLiteral(ListLiteral node) {
    return _translateListOrSet(node, node.typeArgument, node.expressions,
        isConst: node.isConst, isSet: false);
  }

  @override
  TreeNode visitSetLiteral(SetLiteral node) {
    return _translateListOrSet(node, node.typeArgument, node.expressions,
        isConst: node.isConst, isSet: true);
  }
}
