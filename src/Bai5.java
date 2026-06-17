public class Bai5 {
    static void main() {
        String s = "A man, a plan, a canal: Panama";
        System.out.println(isPalindrome(s));
    }

    public static boolean isPalindrome(String s) {
        if (s.length() == 1) {
            return true;
        }

        // Using regex to remove
        String result = s.replaceAll("[^a-zA-Z0-9]", "").toLowerCase();
        char[] tempResult = result.toCharArray();

        // Next use 2 pointer to swap the word
        int leftPointer = 0;
        int rightPointer = result.length() - 1;
        while (leftPointer < rightPointer) {
            swap(tempResult, leftPointer, rightPointer);
            leftPointer++;
            rightPointer--;
        }

        // Compare the final word
        return result.equals(new String(tempResult));
    }

    public static void swap (char[] s, int leftPointer, int rightPointer) {
        char temp = s[leftPointer];
        s[leftPointer] = s[rightPointer];
        s[rightPointer] = temp;
    }
}
