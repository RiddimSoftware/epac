package main

import (
	"database/sql"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
)

// Speech represents a speech from a Hansard debate.
// The struct fields are placeholders and should be updated to match the actual XML structure.
type Speech struct {
	XMLName xml.Name `xml:"Speech"`
	ID      string   `xml:"ID,attr"`
	Content string   `xml:",innerxml"`
	// Add other fields as needed
}

// processSpeechesDir reads the XML files from the speeches directory and populates the speeches table.
func processSpeechesDir(db *sql.DB, dirPath string) error {
	files, err := ioutil.ReadDir(dirPath)
	if err != nil {
		return fmt.Errorf("could not read speeches directory: %w", err)
	}

	for _, file := range files {
		if filepath.Ext(file.Name()) == ".xml" {
			filePath := filepath.Join(dirPath, file.Name())
			if err := processSpeechFile(db, filePath); err != nil {
				return err
			}
		}
	}

	return nil
}

// processSpeechFile reads a single XML file and populates the speeches table.
func processSpeechFile(db *sql.DB, filePath string) error {
	xmlFile, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("could not open speech file: %w", err)
	}
	defer xmlFile.Close()

	byteValue, _ := ioutil.ReadAll(xmlFile)

	var speech Speech
	// The following is a placeholder. The actual implementation will depend on the XML format.
	err = xml.Unmarshal(byteValue, &speech)
	if err != nil {
		// It's possible the XML file contains multiple speeches or a different structure.
		// This is a placeholder for the actual parsing logic.
		fmt.Printf("could not unmarshal speech from %s: %v\n", filePath, err)
		return nil // Continue processing other files
	}

	fmt.Printf("Processing speech: %+v\n", speech)
	// Insert the speech into the database
	// _, err = db.Exec("INSERT INTO speeches (id, content) VALUES ($1, $2)", speech.ID, speech.Content)
	// if err != nil {
	//  return fmt.Errorf("could not insert speech: %w", err)
	// }

	return nil
}
