package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

const modulePath = "epac/lobbying-index"

func TestUsecaseLayerDoesNotImportS3OrAWS(t *testing.T) {
	for _, file := range productionGoFiles(t, "internal/usecase") {
		for _, importPath := range importsForFile(t, file) {
			switch {
			case importPath == modulePath+"/internal/adapter/s3" || strings.HasPrefix(importPath, modulePath+"/internal/adapter/s3/"):
				t.Errorf("%s imports %s - the application layer must not depend on the S3 detail. Keep S3 hydrate/persist in the phase router (main.go). See docs/architecture/use-case-catalog.md.", rel(file), importPath)
			case importPath == "github.com/aws/aws-sdk-go-v2" || strings.HasPrefix(importPath, "github.com/aws/aws-sdk-go-v2/"):
				t.Errorf("%s imports %s - the application layer must not depend on the AWS SDK. Keep AWS/S3 hydrate/persist in adapters or the phase router (main.go). See docs/architecture/use-case-catalog.md.", rel(file), importPath)
			}
		}
	}
}

func TestPhaseUsecasesDoNotDependOnOtherPhases(t *testing.T) {
	phases := []phaseBoundary{
		{
			name:    "ingest OCL data phase",
			file:    "internal/usecase/usecase.go",
			symbols: []string{"IngestOCLData", "IngestOCLDataResult", "NewIngestOCLData"},
		},
		{
			name: "MP lobbying aggregation phase",
			file: "internal/usecase/mp_aggregation.go",
			symbols: []string{
				"BuildMPLobbyingTables",
				"BuildMPLobbyingTablesResult",
				"NewBuildMPLobbyingTables",
			},
		},
		{
			name: "organization and bill-context aggregation phase",
			file: "internal/usecase/org_aggregation.go",
			symbols: []string{
				"BuildOrganizationTables",
				"BuildOrganizationTablesResult",
				"NewBuildOrganizationTables",
				"BuildBillContextTables",
				"BuildBillContextTablesResult",
				"NewBuildBillContextTables",
			},
		},
		{
			name: "minister prebake phase",
			file: "internal/usecase/minister_prebake.go",
			symbols: []string{
				"PreBakeMinisterCommunications",
				"PreBakeMinisterCommunicationsResult",
				"NewPreBakeMinisterCommunications",
			},
		},
	}

	phaseByFile := make(map[string]phaseBoundary, len(phases))
	ownerBySymbol := make(map[string]phaseBoundary)
	for _, phase := range phases {
		phaseByFile[phase.file] = phase
		for _, symbol := range phase.symbols {
			ownerBySymbol[symbol] = phase
		}
	}

	for _, file := range productionGoFiles(t, "internal/usecase") {
		phase, ok := phaseByFile[rel(file)]
		if !ok {
			t.Errorf("%s is a lobbying-index usecase file without a phase boundary entry - add it to TestPhaseUsecasesDoNotDependOnOtherPhases so cross-phase dependencies stay mechanical.", rel(file))
			continue
		}

		for _, importPath := range importsForFile(t, file) {
			if importPath == modulePath+"/internal/usecase" || strings.HasPrefix(importPath, modulePath+"/internal/usecase/") {
				t.Errorf("%s imports %s - phase use cases must not import another phase use case. Keep sequencing in the Step Functions definition or phase router, not inside Go use cases.", rel(file), importPath)
			}
		}

		parsedFile := parseFile(t, file, 0)
		ast.Inspect(parsedFile, func(node ast.Node) bool {
			identifier, ok := node.(*ast.Ident)
			if !ok {
				return true
			}
			owner, ok := ownerBySymbol[identifier.Name]
			if !ok || owner.file == phase.file {
				return true
			}
			t.Errorf("%s references %s from the %s - phase use cases must not invoke another phase's use case. Keep sequencing in the Step Functions definition or phase router, not inside internal/usecase.", rel(file), identifier.Name, owner.name)
			return true
		})
	}
}

func TestMainDoesNotImportDatabaseSQL(t *testing.T) {
	for _, importPath := range importsForFile(t, "main.go") {
		if importPath == "database/sql" {
			t.Errorf("main.go imports database/sql - orchestration must not open DB handles directly. Keep DB-handle ownership in use cases/adapters and let main.go wire phases only. See docs/architecture/use-case-catalog.md.")
		}
	}
}

type phaseBoundary struct {
	name    string
	file    string
	symbols []string
}

func productionGoFiles(t *testing.T, root string) []string {
	t.Helper()

	var files []string
	if err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if strings.HasSuffix(path, ".go") && !strings.HasSuffix(path, "_test.go") {
			files = append(files, filepath.ToSlash(path))
		}
		return nil
	}); err != nil {
		t.Fatalf("walk %s: %v", root, err)
	}
	sort.Strings(files)
	return files
}

func importsForFile(t *testing.T, path string) []string {
	t.Helper()

	parsedFile := parseFile(t, path, parser.ImportsOnly)
	imports := make([]string, 0, len(parsedFile.Imports))
	for _, spec := range parsedFile.Imports {
		importPath, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			t.Fatalf("parse import path in %s: %v", rel(path), err)
		}
		imports = append(imports, importPath)
	}
	return imports
}

func parseFile(t *testing.T, path string, mode parser.Mode) *ast.File {
	t.Helper()

	parsedFile, err := parser.ParseFile(token.NewFileSet(), path, nil, mode)
	if err != nil {
		t.Fatalf("parse %s: %v", rel(path), err)
	}
	return parsedFile
}

func rel(path string) string {
	relative, err := filepath.Rel(".", path)
	if err != nil {
		return filepath.ToSlash(path)
	}
	return filepath.ToSlash(relative)
}
