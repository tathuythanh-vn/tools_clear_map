import java.util.Stack;

class Syntax2 {
    static void main() {
        System.out.println(stringToInteger("   -42"));
    }

    public static Integer stringToInteger(String s) {
        String regex = "[0-9]+";
        int result = 0;

        s = s.trim();

        StringBuffer sb = new StringBuffer();


        for (int i = 0; i < s.length(); i++) {
            if (!Character.isDigit(s.charAt(i))) {
                continue;
            }

            if (s.charAt(i) == '-') {
                sb.append(s.charAt(i));
            }

            if (Character.isDigit(s.charAt(i))) {
                sb.append(s.charAt(i));
            }
        }

        return Integer.parseInt(sb.toString());
    }
}