package legisinfo

import (
	"reflect"
	"testing"

	"epac/bills-indexer/internal/domain"
)

func TestParseBillXML(t *testing.T) {
	xmlData := []byte(`<?xml version="1.0" encoding="utf-8"?>
<Bill>
  <Body>
    <Heading level="1"><TitleText>Some Heading</TitleText></Heading>
    <Section type="amending">
      <Label>1</Label>
      <Text>This is clause one text with a newline
      and extra  spaces.</Text>
      <AmendedText>
        <Subparagraph>
          <Label>(a)</Label>
          <Text>Subparagraph text</Text>
        </Subparagraph>
      </AmendedText>
    </Section>
    <Section>
      <Label>2</Label>
      <Text>This is clause two text.</Text>
    </Section>
  </Body>
</Bill>`)

	expected := []domain.VersionSection{
		{
			Label: "1",
			Text:  "This is clause one text with a newline and extra spaces. (a) Subparagraph text",
		},
		{
			Label: "2",
			Text:  "This is clause two text.",
		},
	}

	sections, err := parseBillXML(xmlData)
	if err != nil {
		t.Fatalf("parseBillXML: %v", err)
	}

	if !reflect.DeepEqual(sections, expected) {
		t.Errorf("parsed sections mismatch.\nExpected: %+v\nGot:      %+v", expected, sections)
	}
}
