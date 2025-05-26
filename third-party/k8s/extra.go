package main

import (
  "strings"
  "os"
  "path"

  "cuelang.org/go/cue"
  "cuelang.org/go/cue/ast"
  "cuelang.org/go/cue/cuecontext"
  "cuelang.org/go/cue/format"
  "cuelang.org/go/cue/load"
)

func main() {
  outDir := os.Args[1]
  packages := os.Args[2:]

  ctx := cuecontext.New()

  for _, pkgDir := range packages {
    instances := load.Instances([]string{pkgDir}, &load.Config{})
    pkg := instances[0].PkgName
    values, err := ctx.BuildInstances(instances)
    if err != nil {
      panic(err)
    }

    resources := []ast.Decl{
      &ast.Package {
        Name: &ast.Ident{
          Name: pkg,
        },
      },
    }

    for _, value := range values {
      fields, err := value.Fields(cue.Definitions(true))
      if err != nil {
        panic(err)
      }

      group := value.LookupPath(cue.MakePath(cue.Def("#GroupName")))
      groupStr, err := group.String()
      if err != nil {
        panic(err)
      }

      for fields.Next() {
        value := fields.Value()

        var groupVersion []string
        if groupStr != "" {
          groupVersion = []string{groupStr,pkg}
        } else {
          groupVersion = []string{pkg}
        }

        kind := value.LookupPath(cue.MakePath(cue.Str("kind").Optional()))
        if kind.Err() != nil {
          continue
        }
        apiVersion := value.LookupPath(cue.MakePath(cue.Str("apiVersion").Optional()))
        if apiVersion.Err() != nil {
          continue
        }
        resources = append(resources, &ast.Field {
          Label: ast.NewIdent(fields.Selector().String()),
          Value: ast.NewStruct(&ast.Field{
            Label: ast.NewIdent("kind"),
            Value: ast.NewString(strings.TrimPrefix(fields.Selector().String(), "#")),
          }, &ast.Field {
            Label: ast.NewIdent("apiVersion"),
            Value: ast.NewString(strings.Join(groupVersion, "/")),
          }),
        })
      }
    }

    out, err := format.Node(&ast.File{
      Decls: resources,
    })
    if err != nil {
      panic(err)
    }

    err = os.MkdirAll(path.Join(outDir, pkgDir), 0755)
    if err != nil {
      panic(err)
    }
    err = os.WriteFile(path.Join(outDir, pkgDir, "gvk.cue"), out, 0644)
    if err != nil {
      panic(err)
    }
  }
}
