"""Regression cases for the structural options layout scan."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from options_layout import findings


class OptionsLayoutTests(unittest.TestCase):
    def test_detects_split_micro_menu_rows_and_accepts_packing(self):
        prefix = """
            W:SectionHeader(parent, "MICRO MENU", y)
        """
        split = """
            local menuRow = W:DualRow(parent, y,
                {text = 'Menu Elements'}, iconStyleCfg or EllesmereUI . BlankRowCfg ())
            W:DualRow(parent, y, {text = 'Show Guild Notes'}, EllesmereUI.BlankRowCfg())
        """
        packed = """
            W:DualRow(parent, y, {text = 'Menu Elements'}, iconStyleCfg or notesCfg)
            if iconStyleCfg then
                W:DualRow(parent, y, notesCfg, EllesmereUI.BlankRowCfg())
            end
        """
        [(section, blank, following)] = findings(prefix + split)
        self.assertEqual((section, blank.left, following.left),
                         ("MICRO MENU", "Menu Elements", "Show Guild Notes"))
        self.assertEqual(list(findings(prefix + packed)), [])

    def test_final_blank_width_and_independent_streams(self):
        source = """
            W:SectionHeader(parent, "FIRST", y)
            W:DualRow(parent, y, one, EUI.BlankRowCfg())
            W:DualRow(parent, y, fullWidth, nil)
            W:DualRow(parent, y, final, {type = "label", text = ""})
            W:DualRow(otherParent, y, unrelated, second)
            W:SectionHeader(parent, "SECOND", y)
            W:DualRow(parent, y, first, second)
            W:DualRow(parent, y, last, EUI.BlankRowCfg())
        """
        self.assertEqual(list(findings(source)), [])

    def test_empty_label_inside_callback_page_is_detected(self):
        source = """
            RegisterPage("Test", function()
                W:SectionHeader(parent, "TEST", y)
                W:DualRow(parent, y, one, {type = 'spacer'})
                -- W:SectionHeader(parent, "comment", y)
                W:DualRow(parent, y, two, three)
            end)
        """
        [(section, blank, following)] = findings(source)
        self.assertEqual((section, blank.left, following.left), ("TEST", "one", "two"))

    def test_alternative_branches_are_not_treated_as_consecutive(self):
        source = """
            if condition then
                W:DualRow(parent, y, left, EllesmereUI.BlankRowCfg())
            else
                W:DualRow(parent, y, one, two)
            end
        """
        self.assertEqual(list(findings(source)), [])


if __name__ == "__main__":
    unittest.main()
