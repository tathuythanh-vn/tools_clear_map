import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public class Bai7 {
    static void main() {
        String s = "anagram";
        String t = "nagaram";
        System.out.println(isAnagram(s, t));
    }

    public static boolean isAnagram(String s, String t) {
        // Create a set to store char in String s
        Map<Character, Integer> chars = new HashMap();

        // Loop through String s and store appeared char
        for (int i = 0; i < s.length(); i++) {
            char curChar = s.charAt(i);
            if (chars.containsKey(curChar)) {
                chars.computeIfPresent(curChar, (key, val) -> val + 1);
            } else {
                chars.put(curChar, 1);
            }
        }

        // Check String t use diff char
        for (int i = 0; i < t.length(); i++) {
            char curChar = t.charAt(i);
            boolean isFound = chars.containsKey(t.charAt(i));
            if (!isFound) {
                return false;
            } else {
                chars.computeIfPresent(curChar, (key, val) -> val - 1);
                if (chars.get(curChar) <= 0){
                    chars.remove(curChar);
                }
            }
        }

        return chars.isEmpty();
    }
}
