package app

import utest._

object TutorialTest extends TestSuite {

  def tests = Tests {
    test("HelloWorld") {
      assert(1 == 1)
    }
  }
}
