import java.util.*;

// https://leetcode.com/problems/valid-parentheses
public class Bai2 {

    public static void main(String[] args) {
        String s = "){";
        System.out.println(Solution(s));
    }

    public static boolean Solution(String s) {
        // O(n)
        if (s.length() % 2 == 1) {
            return false;
        }

        Stack<Character> stack = new Stack<>();

        for (int i = 0; i < s.length(); i++) {
            char currentChar = s.charAt(i);

            boolean isOpeningBracket =
                    currentChar == '(' || currentChar == '{' || currentChar == '[';

            if (isOpeningBracket) {
                stack.push(currentChar);
            } else {
                // Check stack value
                if (stack.empty()) {
                    return false;
                }

                char previousChar = stack.peek();
                boolean isMatched = checkMatchOpen(previousChar, currentChar);

                if (!isMatched) {
                    return false;
                }

                stack.pop();
            }
        }

        return stack.empty();
    }

    public static boolean checkMatchOpen(char target, char input) {
        return switch (input) {
            case '}' -> target == '{';
            case ']' -> target == '[';
            case ')' -> target == '(';
            default -> false;
        };
    }
}
