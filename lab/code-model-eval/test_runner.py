#!/usr/bin/env python3
import json
import unittest

import runner


class RunnerTests(unittest.TestCase):
    def test_current_event_shape(self):
        raw = json.dumps({"type": "text", "part": {"type": "text", "text": "why\nFINAL_ANSWER: C"}})
        text, tools, errors = runner.parse_events(raw)
        self.assertEqual("C", runner.extract_answer(text, "mcq"))
        self.assertEqual((tools, errors), (0, 0))

    def test_nested_tool_is_detected(self):
        raw = json.dumps({"type": "message", "part": {"type": "tool_use", "tool": "bash"}})
        _, tools, _ = runner.parse_events(raw)
        self.assertGreater(tools, 0)

    def test_crux_answer_preserves_repr(self):
        text = "Reasoning\nFINAL_ANSWER: [(2, 'x'), None]"
        self.assertEqual("[(2, 'x'), None]", runner.extract_answer(text, "crux_output"))


if __name__ == "__main__":
    unittest.main()
